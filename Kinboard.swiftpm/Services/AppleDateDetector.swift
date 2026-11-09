import Foundation

/// Date finding with Apple's `NSDataDetector` — the same engine that underlines dates in
/// Mail and Messages. It understands "next Tuesday", "11/14", "Dec 3 at 6:30pm" and more.
struct AppleDateDetector: DateDetecting {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    func detectDates(in text: String) -> [DetectedDate] {
        guard let detector = Self.detector else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, options: [], range: range).compactMap { match in
            guard let date = match.date, let r = Range(match.range, in: text) else { return nil }
            let matched = String(text[r])
            // Whole seconds, so dates survive the save file's ISO 8601 round trip exactly.
            return DetectedDate(range: r,
                                date: Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.rounded(.down)),
                                duration: match.duration > 0 ? match.duration : nil,
                                hasTime: DateText.hasTime(matched),
                                hasDay: DateText.hasDay(matched))
        }
    }
}
