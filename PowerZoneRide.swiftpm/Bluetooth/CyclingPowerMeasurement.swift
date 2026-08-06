import Foundation

/// Decoder for the BLE Cycling Power Measurement characteristic (0x2A63).
///
/// Layout per the Bluetooth SIG Cycling Power Service spec: a 16-bit flags field, then a
/// mandatory signed 16-bit instantaneous power in watts, then a run of optional fields
/// whose presence is announced by the flag bits. The optional fields must be walked in
/// order even when only a later one is wanted, because each one shifts the offset of
/// everything after it.
///
/// The Favero Assioma sets the crank revolution bit, which is where cadence comes from.
struct CyclingPowerMeasurement {
    let instantaneousPower: Int         // watts
    let cumulativeCrankRevolutions: UInt16?
    let lastCrankEventTime: UInt16?     // 1/1024 s, wraps every ~64 s

    init?(data: Data) {
        guard data.count >= 4 else { return nil }
        let bytes = [UInt8](data)

        func u16(_ i: Int) -> UInt16? {
            guard i + 1 < bytes.count else { return nil }
            return UInt16(bytes[i]) | (UInt16(bytes[i + 1]) << 8)
        }

        guard let flags = u16(0), let rawPower = u16(2) else { return nil }
        instantaneousPower = Int(Int16(bitPattern: rawPower))

        var offset = 4
        if flags & (1 << 0) != 0 { offset += 1 }   // pedal power balance
        if flags & (1 << 2) != 0 { offset += 2 }   // accumulated torque
        if flags & (1 << 4) != 0 { offset += 6 }   // wheel revs (u32) + event time (u16)

        if flags & (1 << 5) != 0 {                 // crank revs (u16) + event time (u16)
            cumulativeCrankRevolutions = u16(offset)
            lastCrankEventTime = u16(offset + 2)
        } else {
            cumulativeCrankRevolutions = nil
            lastCrankEventTime = nil
        }
    }
}

/// Turns successive crank readings into RPM.
///
/// Both counters are 16-bit and wrap — revolutions roughly every 18 hours, the event
/// clock every 64 seconds — so the deltas are computed with wrapping subtraction. A zero
/// time delta means the meter re-sent an unchanged sample, which happens whenever the
/// cranks are still; that holds the previous value rather than dividing by zero.
struct CadenceTracker {
    private var lastRevs: UInt16?
    private var lastTime: UInt16?
    private var lastRPM: Double = 0
    private var stillSince: Date?

    mutating func update(revolutions: UInt16?, eventTime: UInt16?) -> Double {
        guard let revs = revolutions, let time = eventTime else { return 0 }
        defer { lastRevs = revs; lastTime = time }

        guard let pRevs = lastRevs, let pTime = lastTime else { return lastRPM }

        let dRevs = revs &- pRevs
        let dTime = time &- pTime

        if dTime == 0 {
            // No new crank event. After a couple of seconds of that, call it zero.
            if let since = stillSince, Date().timeIntervalSince(since) > 2.0 { lastRPM = 0 }
            else if stillSince == nil { stillSince = Date() }
            return lastRPM
        }
        stillSince = nil

        let seconds = Double(dTime) / 1024.0
        lastRPM = Double(dRevs) / seconds * 60.0
        if lastRPM > 250 { lastRPM = 0 }  // implausible; treat as a glitched sample
        return lastRPM
    }
}
