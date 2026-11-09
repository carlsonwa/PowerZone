import Foundation

/// iCalendar (.ics) export, so the family calendar can be opened in Apple Calendar,
/// Google Calendar or Outlook.
enum ICSExporter {
    static func calendar(_ events: [FamilyEvent], members: [FamilyMember], calendar: Calendar,
                         now: Date = Date()) -> String {
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Kinboard//Family Calendar//EN",
            "CALSCALE:GREGORIAN",
            "X-WR-CALNAME:Kinboard",
        ]
        for event in events {
            lines += vevent(event, members: members, calendar: calendar, now: now)
        }
        lines.append("END:VCALENDAR")
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    static func vevent(_ e: FamilyEvent, members: [FamilyMember], calendar: Calendar, now: Date) -> [String] {
        let tz = calendar.timeZone.identifier
        var lines = ["BEGIN:VEVENT", "UID:\(e.id.uuidString)@kinboard", "DTSTAMP:\(utc(now))"]
        if e.isAllDay {
            let first = calendar.startOfDay(for: e.start)
            let afterLast = calendar.date(byAdding: .day, value: e.allDaySpan(calendar: calendar) + 1, to: first) ?? first
            lines.append("DTSTART;VALUE=DATE:\(dateOnly(first, calendar))")
            lines.append("DTEND;VALUE=DATE:\(dateOnly(afterLast, calendar))")
        } else {
            // Local time with a TZID, not UTC: a weekly 4 pm practice must stay at 4 pm
            // after the clocks change.
            lines.append("DTSTART;TZID=\(tz):\(local(e.start, calendar))")
            lines.append("DTEND;TZID=\(tz):\(local(max(e.end, e.start), calendar))")
        }
        lines.append("SUMMARY:\(escape(e.title))")
        if !e.location.isEmpty { lines.append("LOCATION:\(escape(e.location))") }
        var description = e.notes
        let people = e.memberIDs.compactMap { id in members.first { $0.id == id }?.name }
        if !people.isEmpty {
            description = (description.isEmpty ? "" : description + "\n\n") + "For: " + people.joined(separator: ", ")
        }
        if !description.isEmpty { lines.append("DESCRIPTION:\(escape(description))") }
        lines.append("CATEGORIES:\(escape(e.area.label))")

        if let rule = e.repeatRule {
            lines.append("RRULE:" + rrule(rule, isAllDay: e.isAllDay, calendar: calendar))
            for key in e.skippedDays.sorted() {
                guard let day = DayKey.date(key, calendar: calendar) else { continue }
                if e.isAllDay {
                    lines.append("EXDATE;VALUE=DATE:\(dateOnly(day, calendar))")
                } else {
                    let t = calendar.dateComponents([.hour, .minute, .second], from: e.start)
                    if let occurrence = calendar.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0,
                                                      second: t.second ?? 0, of: day) {
                        lines.append("EXDATE;TZID=\(tz):\(local(occurrence, calendar))")
                    }
                }
            }
        }

        if e.reminder != .none {
            let minutesBefore: Int
            if e.isAllDay {
                // Relative to midnight: 9 AM on the day, or 9 AM N days before.
                minutesBefore = (e.reminder.rawValue / 1440) * 1440 - ReminderSchedule.allDayHour * 60
            } else {
                minutesBefore = e.reminder.rawValue
            }
            lines += ["BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:\(escape(e.title))",
                      "TRIGGER:\(minutesBefore >= 0 ? "-" : "")PT\(abs(minutesBefore))M", "END:VALARM"]
        }
        lines.append("END:VEVENT")
        return lines
    }

    static func rrule(_ rule: RepeatRule, isAllDay: Bool, calendar: Calendar) -> String {
        var parts = ["FREQ=\(rule.frequency.rawValue.uppercased())"]
        if rule.interval > 1 { parts.append("INTERVAL=\(rule.interval)") }
        if rule.frequency == .weekly, !rule.weekdays.isEmpty {
            let codes = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
            parts.append("BYDAY=" + Recurrence.orderedWeekdays(rule.weekdays, calendar: calendar)
                .map { codes[($0 - 1) % 7] }.joined(separator: ","))
        }
        if let until = rule.until {
            if isAllDay {
                parts.append("UNTIL=\(dateOnly(until, calendar))")
            } else {
                // UNTIL must be UTC when DTSTART has a TZID; use the very end of the last day.
                let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1),
                                             to: calendar.startOfDay(for: until)) ?? until
                parts.append("UNTIL=\(utc(endOfDay))")
            }
        }
        return parts.joined(separator: ";")
    }

    // MARK: Formatting

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
    }

    /// RFC 5545 §3.1: lines longer than 75 octets continue on the next line after a
    /// space, splitting only between characters so UTF-8 sequences stay whole.
    static func fold(_ line: String) -> String {
        var result = ""
        var lineBytes = 0
        for ch in line {
            let size = String(ch).utf8.count
            if lineBytes + size > 75 {
                result += "\r\n "
                lineBytes = 1
            }
            result.append(ch)
            lineBytes += size
        }
        return result
    }

    private static func utc(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d%02d%02dT%02d%02d%02dZ", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
    }

    private static func local(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d%02d%02dT%02d%02d%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
    }

    private static func dateOnly(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year!, c.month!, c.day!)
    }
}

/// CSV exports for spreadsheets, tax time, FSA claims and the pediatrician.
enum CSVExporter {
    static func expenses(_ expenses: [Expense], members: [FamilyMember], calendar: Calendar) -> String {
        func names(_ ids: [UUID]) -> String {
            ids.compactMap { id in members.first { $0.id == id }?.name }.joined(separator: "; ")
        }
        var rows = [["Date", "Description", "Category", "Amount", "For", "Paid By", "Reimbursement", "Notes"]]
        for e in expenses.sorted(by: { $0.date < $1.date }) {
            rows.append([
                DayKey.make(e.date, calendar: calendar),
                e.title,
                e.category.label,
                Money.plain(e.amountCents),
                names(e.memberIDs),
                names(e.paidByID.map { [$0] } ?? []),
                e.reimbursement.label,
                e.notes,
            ])
        }
        return encode(rows)
    }

    static func trackerEntries(_ data: FamilyData, calendar: Calendar) -> String {
        var rows = [["Tracker", "For", "Start", "End", "Minutes", "Value", "Unit", "Note"]]
        let stamp: (Date) -> String = { d in
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: d)
            return String(format: "%04d-%02d-%02d %02d:%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!)
        }
        for entry in data.trackerEntries.sorted(by: { $0.date < $1.date }) {
            guard let tracker = data.tracker(entry.trackerID) else { continue }
            rows.append([
                tracker.name,
                data.member(tracker.memberID)?.name ?? "",
                stamp(entry.date),
                entry.endDate.map(stamp) ?? "",
                entry.duration.map { String(Int(($0 / 60).rounded())) } ?? "",
                entry.value.map { $0 == $0.rounded() ? String(Int($0)) : String(format: "%.2f", $0) } ?? "",
                tracker.unit,
                entry.note,
            ])
        }
        return encode(rows)
    }

    static func encode(_ rows: [[String]]) -> String {
        rows.map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    static func cell(_ value: String) -> String {
        var v = value
        // A leading = + - @ makes spreadsheets run the cell as a formula.
        if let first = v.first, "=+-@".contains(first), Double(v) == nil { v = "'" + v }
        if v.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return v
    }
}
