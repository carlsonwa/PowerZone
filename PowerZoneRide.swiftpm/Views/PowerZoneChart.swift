import Charts
import SwiftUI

/// The power zone graph: the workout's target profile as coloured blocks, with your live
/// output drawn over the top and a playhead at the current moment.
///
/// The whole class is always on screen rather than a scrolling window. On a bike you want
/// to see the shape of what's coming — that a 8-minute Zone 4 block is next — more than
/// you want resolution on the last thirty seconds.
struct PowerZoneChart: View {
    let workout: Workout
    let samples: [RideSample]
    let elapsed: Int
    let ftp: Double
    /// Live rides show the playhead and clip the target to what's ahead; the preview on
    /// the detail screen shows the profile alone.
    var isLive: Bool = true

    private var maxWatts: Double {
        let targetPeak = workout.targetSegments
            .map { max($0.startWatts(ftp: ftp), $0.endWatts(ftp: ftp)) }.max() ?? ftp
        let actualPeak = Double(samples.map(\.watts).max() ?? 0)
        return max(targetPeak, actualPeak) * 1.15
    }

    var body: some View {
        Chart {
            // The target profile, one trapezoid per segment. AreaMark rather than
            // RectangleMark because the older classes ramp their warm-up, and a
            // rectangle can only draw a flat target.
            ForEach(workout.targetSegments) { segment in
                let tint = PowerZones.color(zone: segment.colorZone)
                    .opacity(isLive && segment.end <= elapsed ? 0.35 : 0.75)

                AreaMark(
                    x: .value("Time", segment.start),
                    yStart: .value("Floor", 0),
                    yEnd: .value("Target", segment.startWatts(ftp: ftp)),
                    series: .value("Segment", segment.start)
                )
                .foregroundStyle(tint)

                AreaMark(
                    x: .value("Time", segment.end),
                    yStart: .value("Floor", 0),
                    yEnd: .value("Target", segment.endWatts(ftp: ftp)),
                    series: .value("Segment", segment.start)
                )
                .foregroundStyle(tint)
            }

            // Zone boundaries, so you can read your position against the bands directly.
            ForEach(1...6, id: \.self) { z in
                let watts = PowerZones.upperBounds[z - 1] * ftp
                if watts < maxWatts {
                    RuleMark(y: .value("Zone", watts))
                        .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(.white.opacity(0.18))
                }
            }

            // What you actually produced.
            if isLive {
                ForEach(samples, id: \.time) { s in
                    LineMark(
                        x: .value("Time", s.time),
                        y: .value("Watts", s.watts),
                        series: .value("Series", "actual")
                    )
                    .foregroundStyle(.white)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                    .interpolationMethod(.monotone)
                }

                RuleMark(x: .value("Now", elapsed))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .chartXScale(domain: 0...workout.classLength)
        .chartYScale(domain: 0...maxWatts)
        .chartXAxis {
            AxisMarks(values: axisTimeValues) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel {
                    if let seconds = value.as(Int.self) {
                        Text("\(seconds / 60)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel {
                    if let w = value.as(Double.self) {
                        Text("\(Int(w))")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .chartPlotStyle { $0.background(Color.black.opacity(0.25)) }
    }

    /// A tick every five minutes for classes up to 45, every ten beyond that.
    private var axisTimeValues: [Int] {
        let step = workout.classLength > 2700 ? 600 : 300
        return Array(stride(from: 0, through: workout.classLength, by: step))
    }
}
