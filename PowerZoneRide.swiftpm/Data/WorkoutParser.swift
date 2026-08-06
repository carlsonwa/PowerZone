import Foundation

enum ParseError: LocalizedError {
    case noIntervals
    case noTargetCurve
    case noClassLength
    case inconsistent(String)

    var errorDescription: String? {
        switch self {
        case .noIntervals: return "Couldn't find the interval list on the page."
        case .noTargetCurve: return "Couldn't find the target power curve on the page."
        case .noClassLength: return "Couldn't find the class length on the page."
        case .inconsistent(let why): return "The workout data didn't add up: \(why)."
        }
    }
}

/// Pulls a workout out of a homefitnessbuddy detail page.
///
/// The page has no API and no JSON — the data lives in JavaScript that the site's own
/// timer reads. Three things are extracted:
///
///   `var intervals = [[start, duration, 'zone', ...lookahead], ...]`  — the labelled blocks
///   `dataWarmup.push({x: sec, y: pctFTP}, ...)`                       — opening segment
///   `dataFull.push({x: sec, y: pctFTP}, ...)`                         — the rest
///
/// The two curve arrays must be merged: dataFull starts where dataWarmup ends, so reading
/// only dataFull silently drops the first few minutes of target power.
///
/// This is scraping, so it can break if the site changes. Every parse is validated against
/// the class length before it is handed back — a workout that fails validation is refused
/// rather than drawn wrong, because a plausible-looking but incorrect target profile is
/// worse than no workout at all.
enum WorkoutParser {

    static func parse(html: String, id: Int, fallbackTitle: String = "", fallbackInstructor: String = "") throws -> Workout {
        let intervals = try parseIntervals(html)
        let target = try parseTargetCurve(html)
        guard let classLength = parseClassLength(html) else { throw ParseError.noClassLength }

        try validate(intervals: intervals, target: target, classLength: classLength)

        let meta = parseTitle(html)
        return Workout(
            id: id,
            title: meta.title.isEmpty ? fallbackTitle : meta.title,
            instructor: meta.instructor.isEmpty ? fallbackInstructor : meta.instructor,
            classLength: classLength,
            intervals: intervals,
            target: target
        )
    }

    // MARK: - Pieces

    static func parseIntervals(_ html: String) throws -> [Interval] {
        guard let body = firstMatch(in: html, pattern: #"var intervals\s*=\s*\[(.*?)\n\s*\];"#, group: 1) else {
            throw ParseError.noIntervals
        }
        // Only the first three slots matter. The remaining six are the site's lookahead
        // for its "next up" labels, which we derive from the interval list ourselves.
        let rows = matches(in: body, pattern: #"\[\s*(\d+)\s*,\s*(\d+)\s*,\s*'([^']*)'"#)
        let intervals: [Interval] = rows.compactMap { g in
            guard g.count >= 4, let start = Int(g[1]), let dur = Int(g[2]) else { return nil }
            return Interval(start: start, duration: dur, zone: ZoneCode(rawValue: g[3]))
        }
        if intervals.isEmpty { throw ParseError.noIntervals }
        return intervals
    }

    static func parseTargetCurve(_ html: String) throws -> [TargetPoint] {
        // Order is load-bearing and must not be sorted. The curve is a path, not a set of
        // samples: a step up is drawn as (t,low) -> (t,high) -> (t+d,high) -> (t+d,low),
        // so two points share a timestamp and their order distinguishes the rising edge
        // from the falling one. Sorting reorders those pairs and the segments downstream
        // then tile only a fraction of the class.
        let points = pushedPoints(html, array: "dataWarmup") + pushedPoints(html, array: "dataFull")
        if points.isEmpty { throw ParseError.noTargetCurve }

        // The two arrays meet at a shared point; drop only exact consecutive repeats.
        var deduped: [TargetPoint] = []
        for p in points where deduped.last != p {
            deduped.append(p)
        }
        return deduped
    }

    private static func pushedPoints(_ html: String, array: String) -> [TargetPoint] {
        var out: [TargetPoint] = []
        for call in matches(in: html, pattern: "\(array)\\.push\\((.*?)\\);") {
            guard call.count >= 2 else { continue }
            for g in matches(in: call[1], pattern: #"\{\s*x:\s*(\d+)\s*,\s*y:\s*(\d+)"#) {
                if g.count >= 3, let x = Int(g[1]), let y = Int(g[2]) {
                    out.append(TargetPoint(time: x, percentFTP: y))
                }
            }
        }
        return out
    }

    static func parseClassLength(_ html: String) -> Int? {
        firstMatch(in: html, pattern: #"classLength\s*=\s*(\d+)\s*\*\s*1000"#, group: 1).flatMap(Int.init)
    }

    /// Title looks like "Peloton Power Zone Companion Timer - 30 Minute Power Zone with
    /// Matt Wilpers on 05/18/23 @ 7:30AM ET | Home Fitness Buddy".
    static func parseTitle(_ html: String) -> (title: String, instructor: String) {
        guard let raw = firstMatch(in: html, pattern: #"<title>(.*?)</title>"#, group: 1) else {
            return ("", "")
        }
        var t = raw.replacingOccurrences(of: "Peloton Power Zone Companion Timer - ", with: "")
        if let bar = t.range(of: " | Home Fitness Buddy") { t = String(t[t.startIndex..<bar.lowerBound]) }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)

        var instructor = ""
        if let withRange = t.range(of: " with ") {
            let after = t[withRange.upperBound...]
            if let onRange = after.range(of: " on ") {
                instructor = String(after[after.startIndex..<onRange.lowerBound])
            } else {
                instructor = String(after)
            }
        }
        return (t, instructor.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Validation

    /// Checks the invariants that hold across every workout on the site. These are what
    /// make a silent parser drift loud: intervals tile the timeline exactly, and the
    /// merged curve spans the whole class.
    static func validate(intervals: [Interval], target: [TargetPoint], classLength: Int) throws {
        guard let last = intervals.last else { throw ParseError.noIntervals }
        guard last.end == classLength else {
            throw ParseError.inconsistent("intervals end at \(last.end)s but the class is \(classLength)s")
        }
        for i in 1..<intervals.count where intervals[i].start != intervals[i - 1].end {
            throw ParseError.inconsistent("a gap before the block at \(intervals[i].start)s")
        }
        guard let first = target.first, let lastPoint = target.last else {
            throw ParseError.noTargetCurve
        }
        guard first.time == 0 else {
            throw ParseError.inconsistent("the target curve starts at \(first.time)s, not 0")
        }
        guard lastPoint.time == classLength else {
            throw ParseError.inconsistent("the target curve ends at \(lastPoint.time)s, not \(classLength)s")
        }

        // The segments are what actually gets drawn, so check they tile the class rather
        // than trusting the endpoints. A reordered curve or a dropped ramp still passes
        // the endpoint checks above but leaves gaps here.
        var covered = 0
        var previousEnd: Int?
        for i in 0..<(target.count - 1) {
            let a = target[i], b = target[i + 1]
            guard b.time > a.time else { continue }
            if let previousEnd, previousEnd != a.time {
                throw ParseError.inconsistent("the target profile breaks at \(previousEnd)s")
            }
            covered += b.time - a.time
            previousEnd = b.time
        }
        guard covered == classLength else {
            throw ParseError.inconsistent("the target profile covers \(covered)s of \(classLength)s")
        }
    }

    // MARK: - Regex helpers

    static func matches(in text: String, pattern: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i))
            }
        }
    }

    static func firstMatch(in text: String, pattern: String, group: Int) -> String? {
        guard let m = matches(in: text, pattern: pattern).first, m.count > group else { return nil }
        return m[group]
    }
}
