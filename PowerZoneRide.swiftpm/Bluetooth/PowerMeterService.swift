import Combine
import CoreBluetooth
import Foundation

/// Connects to a BLE power meter and publishes live watts and cadence.
///
/// Targets the standard Cycling Power Service (0x1818), which is what the Favero Assioma
/// advertises. Fitness Machine Service (0x1826) is also scanned for so a smart bike shows
/// up in the list, but only its device name is used — power still comes from 0x1818,
/// which every trainer worth connecting to also exposes.
@MainActor
final class PowerMeterService: NSObject, ObservableObject {

    enum ConnectionState: Equatable {
        case poweredOff, unauthorized, idle, scanning, connecting, connected, reconnecting

        var label: String {
            switch self {
            case .poweredOff: return "Bluetooth is off"
            case .unauthorized: return "Bluetooth permission denied"
            case .idle: return "Not connected"
            case .scanning: return "Searching…"
            case .connecting: return "Connecting…"
            case .connected: return "Connected"
            case .reconnecting: return "Reconnecting…"
            }
        }
    }

    struct Discovered: Identifiable, Equatable {
        let id: UUID
        let name: String
        let rssi: Int
    }

    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var watts: Int = 0
    @Published private(set) var cadence: Int = 0
    @Published private(set) var connectedName: String?
    @Published private(set) var discovered: [Discovered] = []
    /// Set when the meter stops sending, so the ride screen can show stale data as stale.
    @Published private(set) var lastSampleAt: Date?

    private static let powerService = CBUUID(string: "1818")
    private static let powerMeasurement = CBUUID(string: "2A63")
    private static let fitnessMachine = CBUUID(string: "1826")

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var cadenceTracker = CadenceTracker()
    private var peripherals: [UUID: CBPeripheral] = [:]

    /// Reconnect to the same meter across launches without making the user pick again.
    private var rememberedID: UUID? {
        get { UserDefaults.standard.string(forKey: "meterID").flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "meterID") }
    }

    /// `nonisolated` so this can be built in a `@StateObject` property initializer. Only
    /// stored properties are touched here, so there is nothing to isolate.
    nonisolated override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Control

    func startScanning() {
        guard central.state == .poweredOn else { return }
        discovered.removeAll()
        peripherals.removeAll()
        state = .scanning
        central.scanForPeripherals(withServices: [Self.powerService, Self.fitnessMachine])
    }

    func stopScanning() {
        central.stopScan()
        if state == .scanning { state = .idle }
    }

    func connect(_ id: UUID) {
        guard let p = peripherals[id] else { return }
        central.stopScan()
        state = .connecting
        peripheral = p
        p.delegate = self
        central.connect(p)
    }

    func disconnect() {
        rememberedID = nil
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        connectedName = nil
        watts = 0
        cadence = 0
        state = .idle
    }

    /// True when a sample arrived recently enough to trust the numbers on screen.
    var isReceivingData: Bool {
        guard let last = lastSampleAt else { return false }
        return Date().timeIntervalSince(last) < 5
    }

    private func reconnectToRemembered() {
        guard let id = rememberedID,
              let known = central.retrievePeripherals(withIdentifiers: [id]).first
        else {
            startScanning()
            return
        }
        peripherals[id] = known
        state = .connecting
        peripheral = known
        known.delegate = self
        central.connect(known)
    }
}

// MARK: - CBCentralManagerDelegate

extension PowerMeterService: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                if rememberedID != nil { reconnectToRemembered() } else { state = .idle }
            case .unauthorized:
                state = .unauthorized
            case .poweredOff:
                state = .poweredOff
            default:
                state = .idle
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name ?? "Unknown device"
        let id = peripheral.identifier
        let rssi = RSSI.intValue

        Task { @MainActor in
            peripherals[id] = peripheral
            let entry = Discovered(id: id, name: name, rssi: rssi)
            if let i = discovered.firstIndex(where: { $0.id == id }) {
                discovered[i] = entry
            } else {
                discovered.append(entry)
                discovered.sort { $0.rssi > $1.rssi }  // nearest first
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            state = .connected
            connectedName = peripheral.name
            rememberedID = peripheral.identifier
            cadenceTracker = CadenceTracker()
            peripheral.discoverServices([Self.powerService])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            watts = 0
            cadence = 0
            // Pedals sleep when you stop turning them; keep trying so the ride survives
            // a coasting stretch or a dropped link mid-interval.
            guard rememberedID == peripheral.identifier else {
                state = .idle
                return
            }
            state = .reconnecting
            central.connect(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            state = rememberedID == nil ? .idle : .reconnecting
            if rememberedID != nil { central.connect(peripheral) }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension PowerMeterService: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for s in services where s.uuid == Self.powerService {
            peripheral.discoverCharacteristics([Self.powerMeasurement], for: s)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        guard let chars = service.characteristics else { return }
        for c in chars where c.uuid == Self.powerMeasurement {
            peripheral.setNotifyValue(true, for: c)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        guard characteristic.uuid == Self.powerMeasurement,
              let data = characteristic.value,
              let m = CyclingPowerMeasurement(data: data)
        else { return }

        Task { @MainActor in
            watts = max(0, m.instantaneousPower)
            cadence = Int(cadenceTracker.update(revolutions: m.cumulativeCrankRevolutions,
                                                eventTime: m.lastCrankEventTime).rounded())
            lastSampleAt = Date()
            if state != .connected { state = .connected }
        }
    }
}
