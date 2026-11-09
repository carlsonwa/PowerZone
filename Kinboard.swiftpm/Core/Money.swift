import Foundation

/// Amounts are whole cents everywhere in Kinboard. These helpers turn text into cents and
/// back without going through floating point.
enum Money {
    /// Parses what someone types into an amount field: "12", "12.5", "$1,234.56",
    /// or "12,50" where the decimal separator is a comma. Returns nil for anything else.
    static func parseInput(_ text: String, decimalSeparator: String = ".") -> Int? {
        var s = text.trimmingCharacters(in: .whitespaces)
        s = String(s.filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" })
        guard !s.isEmpty else { return nil }
        let negative = s.hasPrefix("-")
        s = s.replacingOccurrences(of: "-", with: "")
        if decimalSeparator == "," {
            s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else {
            s = s.replacingOccurrences(of: ",", with: "")
        }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let whole = String(parts[0])
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard !(whole.isEmpty && fraction.isEmpty),
              whole.allSatisfy(\.isNumber), fraction.allSatisfy(\.isNumber),
              whole.count <= 12 else { return nil }

        var cents = (Int(whole) ?? 0) * 100
        let digits = Array(fraction)
        if digits.count >= 1 { cents += Int(String(digits[0]))! * 10 }
        if digits.count >= 2 { cents += Int(String(digits[1]))! }
        if digits.count >= 3, Int(String(digits[2]))! >= 5 { cents += 1 }
        return negative ? -cents : cents
    }

    /// "1234.50" — for CSV files and text fields, never for display (use a currency format there).
    static func plain(_ cents: Int) -> String {
        let sign = cents < 0 ? "-" : ""
        let a = abs(cents)
        return "\(sign)\(a / 100).\(String(format: "%02d", a % 100))"
    }

    // MARK: Finding amounts in prose

    private static let dollarPattern = try! NSRegularExpression(
        pattern: #"\$\s?((?:\d{1,3}(?:,\d{3})+)|\d+)(?:\.(\d{1,2}))?(?!\d)"#)
    private static let wordPattern = try! NSRegularExpression(
        pattern: #"(?<![\d.,$])(\d+)(?:\.(\d{2}))?\s?(?:dollars|bucks|usd)\b"#,
        options: [.caseInsensitive])

    /// Dollar amounts written in a message: "$15", "$1,200.00", "20 dollars".
    static func amounts(in text: String) -> [(range: Range<String.Index>, cents: Int)] {
        var found: [(Range<String.Index>, Int)] = []
        let ns = NSRange(text.startIndex..., in: text)
        for pattern in [dollarPattern, wordPattern] {
            for match in pattern.matches(in: text, range: ns) {
                guard let range = Range(match.range, in: text),
                      let wholeRange = Range(match.range(at: 1), in: text) else { continue }
                if found.contains(where: { $0.0.overlaps(range) }) { continue }
                let whole = Int(text[wholeRange].replacingOccurrences(of: ",", with: "")) ?? 0
                var cents = whole * 100
                if let fr = Range(match.range(at: 2), in: text) {
                    let f = String(text[fr])
                    cents += f.count == 1 ? (Int(f) ?? 0) * 10 : (Int(f) ?? 0)
                }
                if cents > 0 { found.append((range, cents)) }
            }
        }
        return found.sorted { $0.0.lowerBound < $1.0.lowerBound }.map { (range: $0.0, cents: $0.1) }
    }
}
