import Combine
import Foundation
import SwiftUI
import UIKit   // isIdleTimerDisabled — keeps the screen awake mid-ride

struct RideSample: Equatable {
    let time: Int       // seconds from class start
    let watts: Int
    let cadence: Int
}

/// Drives the clock during a ride and records what you actually produced.
///
/// The clock is anchored to a wall-clock start date rather than incremented per tick, so
/// a dropped frame or a busy main thread can't make the ride drift out of sync with the
/// class — which matters, because you're riding this alongside a video that has its own
/// timeline and no way to talk to us.
@MainActor
final class RideEngine: ObservableObject {

    enum Phase: Equatable { case ready, running, paused, finished }

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var elapsed: Int = 0
    @Published private(set) var samples: [RideSample] = []
    /// Downsampled copy for the chart; the full set is kept for export.
    @Published private(set) var displaySamples: [RideSample] = []

    let workout: Workout
    private let meter: PowerMeterService
    private var ftp: Double

    private var startDate: Date?
    private var pausedElapsed: Int = 0
    /// Manual sync offset in seconds, from the ±1s / ±10s nudges.
    private var offset: Int = 0
    private var timer: AnyCancellable?

    private let maxDisplayPoints = 600

    /// `nonisolated` so `RideView` can build the engine in its `@StateObject` initializer.
    nonisolated init(workout: Workout, meter: PowerMeterService, ftp: Double) {
        self.workout = workout
        self.meter = meter
        self.ftp = ftp
    }

    // MARK: - Derived state

    var remaining: Int { max(0, workout.classLength - elapsed) }
    var currentInterval: Interval? { workout.interval(at: elapsed) }
    var upcoming: [Interval] { workout.upcomingIntervals(after: elapsed) }

    var secondsLeftInInterval: Int {
        guard let i = currentInterval else { return 0 }
        return max(0, i.end - elapsed)
    }

    var targetWatts: Double? {
        workout.targetWatts(at: elapsed, ftp: ftp)
    }

    var currentZone: Int { PowerZones.zone(forWatts: Double(meter.watts), ftp: ftp) }

    /// A short rolling average, because raw pedal-based power is spiky enough to be hard
    /// to hold a zone against. This is what the big number and the chart line show.
    var smoothedWatts: Int {
        let window = 3
        let recent = samples.suffix(window)
        guard !recent.isEmpty else { return meter.watts }
        return Int((recent.reduce(0) { $0 + $1.watts } / recent.count))
    }

    // MARK: - Control

    func start() {
        guard phase == .ready || phase == .paused else { return }
        startDate = Date().addingTimeInterval(-Double(pausedElapsed))
        phase = .running
        UIApplication.shared.isIdleTimerDisabled = true
        timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func pause() {
        guard phase == .running else { return }
        pausedElapsed = elapsed
        phase = .paused
        timer?.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func finish() {
        phase = .finished
        timer?.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Nudge the clock to line up with the class, mirroring the website's ±1s / ±10s
    /// buttons. Positive skips ahead.
    func nudge(_ seconds: Int) {
        offset += seconds
        tick()
    }

    private func tick() {
        guard let start = startDate, phase == .running else { return }
        let raw = Int(Date().timeIntervalSince(start)) + offset
        elapsed = min(max(0, raw), workout.classLength)

        if meter.isReceivingData {
            samples.append(RideSample(time: elapsed, watts: meter.watts, cadence: meter.cadence))
        } else {
            // Record the gap rather than skipping it, so the chart shows a dropout
            // honestly instead of drawing a straight line across it.
            samples.append(RideSample(time: elapsed, watts: 0, cadence: 0))
        }
        rebuildDisplaySamples()

        if elapsed >= workout.classLength { finish() }
    }

    /// A 60-minute ride is 3,600 points, which is enough to make Swift Charts stutter on
    /// an older iPad. The line is thinned to a fixed budget; the untouched `samples` array
    /// is what gets exported.
    private func rebuildDisplaySamples() {
        guard samples.count > maxDisplayPoints else {
            displaySamples = samples
            return
        }
        let stride = Int(ceil(Double(samples.count) / Double(maxDisplayPoints)))
        var thinned: [RideSample] = []
        thinned.reserveCapacity(maxDisplayPoints + 1)
        var i = 0
        while i < samples.count {
            // Keep the peak of each bucket so hard efforts don't get averaged away.
            let bucket = samples[i..<min(i + stride, samples.count)]
            if let peak = bucket.max(by: { $0.watts < $1.watts }) { thinned.append(peak) }
            i += stride
        }
        if let last = samples.last, thinned.last?.time != last.time { thinned.append(last) }
        displaySamples = thinned
    }

    // MARK: - Summary

    var averageWatts: Int {
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0) { $0 + $1.watts } / samples.count
    }

    /// Normalized Power: 30-second rolling average, raised to the fourth power, averaged,
    /// then the fourth root. Weights hard surges the way the body experiences them.
    var normalizedWatts: Int {
        guard samples.count >= 30 else { return averageWatts }
        var rolling: [Double] = []
        for i in 30...samples.count {
            let window = samples[(i - 30)..<i]
            rolling.append(Double(window.reduce(0) { $0 + $1.watts }) / 30.0)
        }
        let mean = rolling.reduce(0) { $0 + pow($1, 4) } / Double(rolling.count)
        return Int(pow(mean, 0.25))
    }

    var intensityFactor: Double { ftp > 0 ? Double(normalizedWatts) / ftp : 0 }

    var trainingStressScore: Int {
        guard ftp > 0, !samples.isEmpty else { return 0 }
        let hours = Double(samples.count) / 3600.0
        return Int(hours * intensityFactor * intensityFactor * 100)
    }

    /// Seconds spent in each zone 1...7, for the post-ride summary.
    var timeInZones: [Int: Int] {
        var out: [Int: Int] = [:]
        for s in samples where s.watts > 0 {
            let z = PowerZones.zone(forWatts: Double(s.watts), ftp: ftp)
            out[z, default: 0] += 1
        }
        return out
    }
}
