import Foundation
import HealthKit

/// Saves a ride to Apple Health as a cycling workout.
///
/// Whether this works depends on how the app was built. HealthKit needs the
/// `com.apple.developer.healthkit` entitlement, and a Swift Playgrounds `.swiftpm` app
/// product has no way to declare it — the `capabilities:` list covers Bluetooth, camera,
/// location and friends, but not HealthKit. So on the Playgrounds build this is expected
/// to fail at authorization, and the summary screen falls back to the TCX export.
///
/// The code stays here deliberately: it costs nothing when unavailable, and if this
/// project ever moves to a Mac and Xcode, adding the capability there switches it on with
/// no other change. Every failure path is non-fatal by design.
enum HealthKitExporter {

    enum Availability {
        case available
        case unsupported          // no HealthKit on this device
        case notAuthorized        // entitlement missing, or the user declined
    }

    private static let store = HKHealthStore()

    static var isSupported: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Asks for write access. Returns `.notAuthorized` rather than throwing when the
    /// entitlement isn't present, which is the expected outcome on a Playgrounds build.
    static func requestAuthorization() async -> Availability {
        guard isSupported else { return .unsupported }

        let types: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.cyclingPower),
            HKQuantityType(.cyclingCadence)
        ]

        do {
            try await store.requestAuthorization(toShare: types, read: [])
            return .available
        } catch {
            return .notAuthorized
        }
    }

    /// Writes the workout. Throws so the caller can fall back to the file export.
    static func save(engine: RideEngine, startedAt: Date) async throws {
        let end = startedAt.addingTimeInterval(Double(engine.samples.count))

        let config = HKWorkoutConfiguration()
        config.activityType = .cycling
        config.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        try await builder.beginCollection(at: startedAt)

        // Average power over the ride. Per-second series would be richer, but a single
        // aggregate is what Health surfaces for an indoor ride anyway.
        if engine.averageWatts > 0 {
            let quantity = HKQuantity(unit: .watt(), doubleValue: Double(engine.averageWatts))
            let sample = HKQuantitySample(type: HKQuantityType(.cyclingPower),
                                          quantity: quantity,
                                          start: startedAt,
                                          end: end)
            try await builder.addSamples([sample])
        }

        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
    }
}
