import Foundation

/// How an event or task repeats. Deliberately small: the patterns a family calendar
/// actually needs (every day, soccer on Tuesdays and Thursdays, every other week, the 1st
/// of the month, birthdays) and nothing that needs a manual to set up.
struct RepeatRule: Codable, Hashable {
    enum Frequency: String, Codable, CaseIterable, Identifiable {
        case daily, weekly, monthly, yearly
        var id: String { rawValue }
        func label(interval: Int) -> String {
            switch (self, interval) {
            case (.daily, 1): return "Every day"
            case (.weekly, 1): return "Every week"
            case (.weekly, 2): return "Every other week"
            case (.monthly, 1): return "Every month"
            case (.yearly, 1): return "Every year"
            case (.daily, _): return "Every \(interval) days"
            case (.weekly, _): return "Every \(interval) weeks"
            case (.monthly, _): return "Every \(interval) months"
            case (.yearly, _): return "Every \(interval) years"
            }
        }
        var unit: String {
            switch self {
            case .daily: return "day"
            case .weekly: return "week"
            case .monthly: return "month"
            case .yearly: return "year"
            }
        }
    }

    var frequency: Frequency
    var interval: Int = 1
    /// Weekly only. Calendar weekday numbers, 1 = Sunday … 7 = Saturday. Empty means
    /// "the same weekday as the first occurrence".
    var weekdays: [Int] = []
    /// Last day the series may fall on, inclusive.
    var until: Date?

    func summary(calendar: Calendar = .current) -> String {
        var text = frequency.label(interval: max(1, interval))
        if frequency == .weekly, !weekdays.isEmpty {
            let symbols = calendar.shortWeekdaySymbols
            let ordered = Recurrence.orderedWeekdays(weekdays, calendar: calendar)
            text += " on " + ordered.map { symbols[($0 - 1) % 7] }.joined(separator: ", ")
        }
        return text
    }
}

enum Recurrence {
    /// Upper bound on loop iterations, so a malformed rule can never hang the UI.
    static let iterationLimit = 20_000

    /// Calls `body` with each occurrence start of the series that begins at `start`, in
    /// order, beginning with the first one on or after `lowerBound`. Stop by returning
    /// `false`. Every occurrence keeps the wall-clock time of `start`, across DST changes.
    static func enumerateStarts(seriesStart start: Date,
                                rule: RepeatRule?,
                                calendar: Calendar,
                                from lowerBound: Date,
                                _ body: (Date) -> Bool) {
        guard let rule else {
            if start >= lowerBound { _ = body(start) }
            return
        }
        let interval = max(1, rule.interval)
        let untilEnd: Date? = rule.until.flatMap {
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0))
        }

        func emit(_ date: Date) -> Bool {
            if let untilEnd, date >= untilEnd { return false }
            if date < lowerBound || date < start { return true }
            return body(date)
        }

        switch rule.frequency {
        case .weekly where !rule.weekdays.isEmpty:
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: start)?.start else { return }
            let time = calendar.dateComponents([.hour, .minute, .second], from: start)
            let days = orderedWeekdays(rule.weekdays, calendar: calendar)
            let skipWeeks = max(0, (wholeDays(from: weekStart, to: lowerBound, calendar) / 7) / interval - 1)
            var week = skipWeeks
            for _ in 0..<iterationLimit {
                guard let base = calendar.date(byAdding: .day, value: 7 * week * interval, to: weekStart) else { return }
                for weekday in days {
                    let offset = (weekday - calendar.firstWeekday + 7) % 7
                    guard let day = calendar.date(byAdding: .day, value: offset, to: base),
                          let occurrence = calendar.date(bySettingHour: time.hour ?? 0,
                                                          minute: time.minute ?? 0,
                                                          second: time.second ?? 0,
                                                          of: day)
                    else { continue }
                    if !emit(occurrence) { return }
                }
                week += 1
            }

        default:
            let (component, multiplier): (Calendar.Component, Int)
            switch rule.frequency {
            case .daily: (component, multiplier) = (.day, 1)
            case .weekly: (component, multiplier) = (.day, 7)
            case .monthly: (component, multiplier) = (.month, 1)
            case .yearly: (component, multiplier) = (.year, 1)
            }
            // Jump close to the lower bound instead of walking years of history.
            var step = 0
            if lowerBound > start {
                let elapsed: Int
                switch rule.frequency {
                case .daily, .weekly: elapsed = wholeDays(from: start, to: lowerBound, calendar)
                case .monthly: elapsed = calendar.dateComponents([.month], from: start, to: lowerBound).month ?? 0
                case .yearly: elapsed = calendar.dateComponents([.year], from: start, to: lowerBound).year ?? 0
                }
                step = max(0, elapsed / (multiplier * interval) - 1)
            }
            for _ in 0..<iterationLimit {
                // Always offset from the series start, never from the previous occurrence,
                // so Jan 31 → Feb 28 doesn't drag every later month to the 28th.
                guard let occurrence = calendar.date(byAdding: component,
                                                     value: step * multiplier * interval,
                                                     to: start) else { return }
                if !emit(occurrence) { return }
                step += 1
            }
        }
    }

    /// Occurrence starts in `[from, to)`.
    static func starts(seriesStart: Date, rule: RepeatRule?, calendar: Calendar,
                       from: Date, to: Date) -> [Date] {
        var result: [Date] = []
        enumerateStarts(seriesStart: seriesStart, rule: rule, calendar: calendar, from: from) { date in
            guard date < to else { return false }
            result.append(date)
            return true
        }
        return result
    }

    /// The first occurrence on or after `date`.
    static func firstStart(seriesStart: Date, rule: RepeatRule?, calendar: Calendar,
                           onOrAfter date: Date) -> Date? {
        var found: Date?
        enumerateStarts(seriesStart: seriesStart, rule: rule, calendar: calendar, from: date) { d in
            found = d
            return false
        }
        return found
    }

    /// Weekdays sorted the way the user's week runs (Monday first in most of Europe).
    static func orderedWeekdays(_ weekdays: [Int], calendar: Calendar) -> [Int] {
        Array(Set(weekdays.filter { (1...7).contains($0) }))
            .sorted { ($0 - calendar.firstWeekday + 7) % 7 < ($1 - calendar.firstWeekday + 7) % 7 }
    }

    static func wholeDays(from: Date, to: Date, _ calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from),
                                to: calendar.startOfDay(for: to)).day ?? 0
    }
}

// MARK: - Day keys

/// A calendar day as "yyyy-MM-dd" in the given calendar's time zone. Used to mark
/// skipped occurrences so the mark survives the JSON round trip exactly.
enum DayKey {
    static func make(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

// MARK: - Event occurrences

/// One concrete appearance of an event on the calendar. A non-repeating event has
/// exactly one; a weekly practice has one per week.
struct EventOccurrence: Identifiable, Hashable {
    let event: FamilyEvent
    let start: Date
    /// Exclusive end. For all-day events this is midnight after the last day.
    let end: Date

    var id: String { "\(event.id.uuidString)|\(start.timeIntervalSinceReferenceDate)" }
}

extension FamilyEvent {
    /// Number of extra days an all-day event spans beyond its first (0 for a one-day event).
    func allDaySpan(calendar: Calendar) -> Int {
        max(0, Recurrence.wholeDays(from: start, to: end, calendar))
    }

    func occurrence(startingAt occurrenceStart: Date, calendar: Calendar) -> EventOccurrence {
        if isAllDay {
            let day = calendar.startOfDay(for: occurrenceStart)
            let end = calendar.date(byAdding: .day, value: allDaySpan(calendar: calendar) + 1, to: day) ?? day
            return EventOccurrence(event: self, start: day, end: end)
        }
        let length = max(0, end.timeIntervalSince(start))
        return EventOccurrence(event: self, start: occurrenceStart,
                               end: occurrenceStart.addingTimeInterval(length))
    }

    /// Occurrences that overlap `[from, to)`.
    func occurrences(from: Date, to: Date, calendar: Calendar) -> [EventOccurrence] {
        // Start looking early enough to catch an occurrence that began before `from`
        // and is still running.
        let lookBack: Date
        if isAllDay {
            lookBack = calendar.date(byAdding: .day, value: -(allDaySpan(calendar: calendar) + 1), to: from) ?? from
        } else {
            lookBack = from.addingTimeInterval(-max(0, end.timeIntervalSince(start)))
        }
        let skipped = Set(skippedDays)
        let seriesStart = isAllDay ? calendar.startOfDay(for: start) : start
        return Recurrence.starts(seriesStart: seriesStart, rule: repeatRule, calendar: calendar,
                                 from: lookBack, to: to)
            .filter { !skipped.contains(DayKey.make($0, calendar: calendar)) }
            .map { occurrence(startingAt: $0, calendar: calendar) }
            .filter { $0.start < to && ($0.end > from || $0.start >= from) }
    }
}

// MARK: - Reminders

enum ReminderSchedule {
    /// All-day items have no time to count back from, so they remind at this hour.
    static let allDayHour = 9

    static func fireDate(occurrenceStart: Date, isAllDay: Bool, offset: ReminderOffset,
                         calendar: Calendar) -> Date? {
        guard offset != .none else { return nil }
        if isAllDay {
            let daysBefore = offset.rawValue / 1440
            guard let day = calendar.date(byAdding: .day, value: -daysBefore,
                                          to: calendar.startOfDay(for: occurrenceStart)) else { return nil }
            return calendar.date(bySettingHour: allDayHour, minute: 0, second: 0, of: day)
        }
        return occurrenceStart.addingTimeInterval(-Double(offset.rawValue) * 60)
    }

    /// Tasks remind at their due time, or at 9 AM on the due day when they have no time.
    static func fireDate(for task: TaskItem, calendar: Calendar) -> Date? {
        guard task.remind, !task.isDone, let due = task.dueDate else { return nil }
        if task.hasDueTime { return due }
        return calendar.date(bySettingHour: allDayHour, minute: 0, second: 0,
                             of: calendar.startOfDay(for: due))
    }
}

// MARK: - Repeating tasks

extension TaskItem {
    /// The next instance of a repeating task once this one is done: the first occurrence
    /// after both the current due date and the day it was actually completed, so a chore
    /// done three days late doesn't come back already overdue.
    func nextInstance(completedOn completion: Date, calendar: Calendar) -> TaskItem? {
        guard let rule = repeatRule, let due = dueDate else { return nil }
        let latest = max(calendar.startOfDay(for: due), calendar.startOfDay(for: completion))
        guard let after = calendar.date(byAdding: .day, value: 1, to: latest),
              let nextDue = Recurrence.firstStart(seriesStart: due, rule: rule, calendar: calendar,
                                                  onOrAfter: after)
        else { return nil }
        var next = self
        next.id = UUID()
        next.dueDate = nextDue
        next.completedAt = nil
        next.createdAt = completion
        return next
    }
}
