import Foundation

/// A stand-in for NSDataDetector, which swift-corelibs-foundation doesn't implement. It
/// understands only what the checks use — "Thursday, November 12", "Dec 10 at 6:30 PM",
/// a bare weekday, a bare time — so the Linux run tests Kinboard's own logic, and the
/// in-app self-check tests it against the real detector.
struct StubDateDetector: DateDetecting {
    var calendar: Calendar
    var reference: Date

    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let time = #"(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)"#
    private static let full = try! NSRegularExpression(
        pattern: #"(?:(sunday|monday|tuesday|wednesday|thursday|friday|saturday),?\s+)?(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?(?:,?\s+(?:at\s+)?"# + time + ")?",
        options: [.caseInsensitive])
    private static let weekday = try! NSRegularExpression(
        pattern: #"\b(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b(?:\s+(?:at\s+)?"# + time + ")?",
        options: [.caseInsensitive])
    private static let timeOnly = try! NSRegularExpression(pattern: #"\b"# + time, options: [.caseInsensitive])

    func detectDates(in text: String) -> [DetectedDate] {
        var found: [DetectedDate] = []
        let ns = NSRange(text.startIndex..., in: text)
        func group(_ m: NSTextCheckingResult, _ i: Int) -> String? {
            Range(m.range(at: i), in: text).map { String(text[$0]).lowercased() }
        }
        func applyTime(_ m: NSTextCheckingResult, hour: Int, to day: Date) -> Date {
            guard let h = group(m, hour).flatMap({ Int($0) }) else { return day }
            let minute = group(m, hour + 1).flatMap { Int($0) } ?? 0
            let pm = group(m, hour + 2)?.hasPrefix("p") ?? false
            let h24 = (h % 12) + (pm ? 12 : 0)
            return calendar.date(bySettingHour: h24, minute: minute, second: 0, of: day)!
        }
        func add(_ m: NSTextCheckingResult, _ date: Date) {
            guard let r = Range(m.range, in: text), !found.contains(where: { $0.range.overlaps(r) }) else { return }
            let matched = String(text[r])
            found.append(DetectedDate(range: r, date: date, duration: nil,
                                      hasTime: DateText.hasTime(matched), hasDay: DateText.hasDay(matched)))
        }
        let today = calendar.startOfDay(for: reference)

        for m in Self.full.matches(in: text, range: ns) {
            guard let monthName = group(m, 2), let dayNum = group(m, 3).flatMap({ Int($0) }),
                  let month = Self.months.firstIndex(where: { monthName.hasPrefix($0) }) else { continue }
            var year = group(m, 4).flatMap { Int($0) } ?? calendar.component(.year, from: reference)
            var day = calendar.date(from: DateComponents(year: year, month: month + 1, day: dayNum))!
            if group(m, 4) == nil && day < today {
                year += 1
                day = calendar.date(from: DateComponents(year: year, month: month + 1, day: dayNum))!
            }
            add(m, applyTime(m, hour: 5, to: day))
        }
        for m in Self.weekday.matches(in: text, range: ns) {
            guard let name = group(m, 1), let target = Self.weekdays.firstIndex(of: name) else { continue }
            let diff = (target + 1 - calendar.component(.weekday, from: today) + 7) % 7
            let day = calendar.date(byAdding: .day, value: diff, to: today)!
            add(m, applyTime(m, hour: 2, to: day))
        }
        for m in Self.timeOnly.matches(in: text, range: ns) {
            add(m, applyTime(m, hour: 1, to: today))
        }
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }
}
