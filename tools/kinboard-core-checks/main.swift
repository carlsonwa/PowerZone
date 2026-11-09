import Foundation

// Runs Kinboard's self-checks on Linux. See tools/check_kinboard_core.sh.

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "America/New_York")!
let reference = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 8))!
let detector = StubDateDetector(calendar: calendar, reference: reference)

let results = SelfChecks.run(detector: detector)
for r in results {
    print("\(r.passed ? "PASS" : "FAIL")  \(r.name)\(r.detail.isEmpty ? "" : "\n        \(r.detail)")")
}

if CommandLine.arguments.contains("--show-sample") {
    let sample = SampleData.make(now: reference, calendar: calendar, detector: detector)
    for message in sample.messages {
        print("\n— \(message.displayTitle)")
        for s in message.suggestions {
            let when = s.date.map { DayKey.make($0, calendar: calendar) } ?? "no date"
            let amount = s.amountCents.map { " $" + Money.plain($0) } ?? ""
            print("   \(s.kind.label): \(s.title) · \(when)\(s.isAllDay ? "" : " (timed)")\(amount) · \(s.expenseCategory.label)")
        }
    }
}

let failed = results.filter { !$0.passed }.count
print("\n\(results.count - failed)/\(results.count) checks passed")
exit(failed == 0 ? 0 : 1)
