import Foundation

/// One labelled block of the class: "Zone 4 for 8:00".
struct Interval: Identifiable, Equatable {
    let start: Int      // seconds from class start
    let duration: Int   // seconds
    let zone: ZoneCode

    var id: Int { start }
    var end: Int { start + duration }
    func contains(_ t: Int) -> Bool { t >= start && t < end }
}

/// A point on the target power curve, as a percentage of FTP.
struct TargetPoint: Equatable {
    let time: Int       // seconds from class start
    let percentFTP: Int
}

/// One span of the target curve — a trapezoid on the chart.
///
/// Most segments are flat (`startPercent == endPercent`), but older classes ramp their
/// warm-up, climbing from 45% to 90% and back down over about thirteen minutes. Modelling
/// these as rectangles would drop the ramps entirely and leave a quarter of such a class
/// with nothing drawn, so every segment carries a percentage at each end.
struct TargetSegment: Identifiable, Equatable {
    let start: Int
    let end: Int
    let startPercent: Int
    let endPercent: Int

    var id: Int { start }
    var isRamp: Bool { startPercent != endPercent }

    func startWatts(ftp: Double) -> Double { Double(startPercent) / 100.0 * ftp }
    func endWatts(ftp: Double) -> Double { Double(endPercent) / 100.0 * ftp }

    /// Target at a moment inside the segment, interpolated along a ramp.
    func watts(at time: Int, ftp: Double) -> Double {
        guard isRamp, end > start else { return startWatts(ftp: ftp) }
        let progress = Double(time - start) / Double(end - start)
        let pct = Double(startPercent) + (Double(endPercent) - Double(startPercent)) * progress
        return pct / 100.0 * ftp
    }

    /// The zone this segment is colored by. A ramp is named for the harder end, which is
    /// what the rider is working toward.
    var colorZone: Int {
        PowerZones.zone(forPercentFTP: Double(max(startPercent, endPercent)))
    }
}

struct Workout: Identifiable, Equatable {
    let id: Int
    let title: String
    let instructor: String
    let classLength: Int        // seconds
    let intervals: [Interval]
    let target: [TargetPoint]

    var sourceURL: URL? {
        URL(string: "https://app.homefitnessbuddy.com/peloton/powerzone/details/\(id)")
    }

    /// The target curve is a polyline, so every consecutive pair that advances in time is
    /// one segment. Pairs sharing a timestamp are the vertical connectors between blocks
    /// and carry no duration, so they are skipped. These segments tile the class exactly.
    var targetSegments: [TargetSegment] {
        var segments: [TargetSegment] = []
        for i in 0..<max(0, target.count - 1) {
            let a = target[i], b = target[i + 1]
            guard b.time > a.time else { continue }
            segments.append(TargetSegment(start: a.time, end: b.time,
                                          startPercent: a.percentFTP,
                                          endPercent: b.percentFTP))
        }
        return segments
    }

    func interval(at t: Int) -> Interval? {
        intervals.first { $0.contains(t) }
    }

    /// The next `count` intervals after time `t`, for the "coming up" strip.
    func upcomingIntervals(after t: Int, count: Int = 3) -> [Interval] {
        Array(intervals.filter { $0.start > t }.prefix(count))
    }

    func targetSegment(at t: Int) -> TargetSegment? {
        targetSegments.first { t >= $0.start && t < $0.end }
    }

    /// Target watts at a moment, interpolated when the segment is a ramp.
    func targetWatts(at t: Int, ftp: Double) -> Double? {
        targetSegment(at: t).map { $0.watts(at: t, ftp: ftp) }
    }
}
