import Foundation

/// Checks of the logic that's easy to get subtly wrong — repeats, deadlines, money, file
/// formats, and reading messages. They run in the app (Settings → Run Self-Check) against
/// the iPhone's real date detector, and on Linux via `tools/check_kinboard_core.sh`.
enum SelfChecks {
    struct Result: Identifiable {
        let id = UUID()
        let name: String
        let passed: Bool
        let detail: String
    }

    static func run(detector: DateDetecting) -> [Result] {
        var results: [Result] = []
        func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
            results.append(Result(name: name, passed: condition, detail: condition ? "" : detail()))
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        cal.firstWeekday = 1
        func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
            cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
        }
        func key(_ d: Date?) -> String { d.map { DayKey.make($0, calendar: cal) } ?? "nil" }
        func hm(_ d: Date?) -> String {
            guard let d else { return "nil" }
            let c = cal.dateComponents([.hour, .minute], from: d)
            return String(format: "%02d:%02d", c.hour!, c.minute!)
        }

        // MARK: Repeats

        // Monday 2 Nov 2026, soccer Monday and Wednesday at 5:30 pm.
        let soccer = FamilyEvent(title: "Soccer", start: date(2026, 11, 2, 17, 30), end: date(2026, 11, 2, 18, 30),
                                 repeatRule: RepeatRule(frequency: .weekly, weekdays: [2, 4]))
        let soccerDays = soccer.occurrences(from: date(2026, 11, 1), to: date(2026, 11, 15), calendar: cal).map { key($0.start) }
        check("Weekly on Mon & Wed", soccerDays == ["2026-11-02", "2026-11-04", "2026-11-09", "2026-11-11"],
              "got \(soccerDays)")

        // 1 Nov 2026 is the end of daylight saving time in New York; 5:30 pm stays 5:30 pm.
        var octoberSoccer = soccer
        octoberSoccer.start = date(2026, 10, 26, 17, 30)
        octoberSoccer.end = date(2026, 10, 26, 18, 30)
        let across = octoberSoccer.occurrences(from: date(2026, 10, 26), to: date(2026, 11, 3), calendar: cal)
        check("Repeats keep wall-clock time across DST",
              across.count == 3 && across.allSatisfy { hm($0.start) == "17:30" },
              "got \(across.map { key($0.start) + " " + hm($0.start) })")

        let biweekly = FamilyEvent(title: "Library", start: date(2026, 11, 3), end: date(2026, 11, 3), isAllDay: true,
                                   repeatRule: RepeatRule(frequency: .weekly, interval: 2))
        let libraryDays = biweekly.occurrences(from: date(2026, 11, 1), to: date(2026, 12, 15), calendar: cal).map { key($0.start) }
        check("Every other week", libraryDays == ["2026-11-03", "2026-11-17", "2026-12-01"], "got \(libraryDays)")

        let rent = FamilyEvent(title: "Tuition", start: date(2027, 1, 31, 9), end: date(2027, 1, 31, 10),
                               repeatRule: RepeatRule(frequency: .monthly))
        let rentDays = rent.occurrences(from: date(2027, 1, 1), to: date(2027, 5, 1), calendar: cal).map { key($0.start) }
        check("Monthly on the 31st clamps to month end, then returns",
              rentDays == ["2027-01-31", "2027-02-28", "2027-03-31", "2027-04-30"], "got \(rentDays)")

        var skipping = soccer
        skipping.skippedDays = ["2026-11-04"]
        let afterSkip = skipping.occurrences(from: date(2026, 11, 1), to: date(2026, 11, 8), calendar: cal).map { key($0.start) }
        check("Deleting one occurrence skips just that day", afterSkip == ["2026-11-02"], "got \(afterSkip)")

        var limited = soccer
        limited.repeatRule?.until = date(2026, 11, 9)
        let untilDays = limited.occurrences(from: date(2026, 11, 1), to: date(2026, 12, 1), calendar: cal).map { key($0.start) }
        check("Repeat end date is inclusive", untilDays == ["2026-11-02", "2026-11-04", "2026-11-09"], "got \(untilDays)")

        let longAgo = FamilyEvent(title: "Daily vitamin", start: date(2019, 3, 10, 8), end: date(2019, 3, 10, 8),
                                  repeatRule: RepeatRule(frequency: .daily))
        let todayHits = longAgo.occurrences(from: date(2026, 11, 9), to: date(2026, 11, 10), calendar: cal)
        check("Old daily series lands on today", todayHits.count == 1 && hm(todayHits.first?.start) == "08:00",
              "got \(todayHits.map { key($0.start) + " " + hm($0.start) })")

        let trip = FamilyEvent(title: "Grandma visiting", start: date(2026, 11, 20), end: date(2026, 11, 23), isAllDay: true)
        let midTrip = trip.occurrences(from: date(2026, 11, 22), to: date(2026, 11, 23), calendar: cal)
        let afterTrip = trip.occurrences(from: date(2026, 11, 24), to: date(2026, 11, 25), calendar: cal)
        check("Multi-day all-day event covers its middle and stops after its last day",
              midTrip.count == 1 && afterTrip.isEmpty, "mid \(midTrip.count), after \(afterTrip.count)")

        // MARK: Tasks

        let chore = TaskItem(title: "Recycling", dueDate: date(2026, 11, 4), repeatRule: RepeatRule(frequency: .weekly))
        let early = chore.nextInstance(completedOn: date(2026, 11, 3, 20), calendar: cal)
        check("Weekly chore done early comes back next week", key(early?.dueDate) == "2026-11-11", "got \(key(early?.dueDate))")
        let late = chore.nextInstance(completedOn: date(2026, 11, 12, 9), calendar: cal)
        check("Chore done late isn't already overdue", key(late?.dueDate) == "2026-11-18", "got \(key(late?.dueDate))")

        var data = FamilyData()
        data.tasks = [chore]
        data.completeTask(id: chore.id, at: date(2026, 11, 4, 18), calendar: cal)
        check("Completing a repeating task adds the next one",
              data.tasks.count == 2 && data.tasks.filter { !$0.isDone }.count == 1, "tasks \(data.tasks.count)")

        let overdue = TaskItem(title: "Form", dueDate: date(2026, 11, 8))
        check("Task due yesterday is overdue; due today is not",
              overdue.isOverdue(now: date(2026, 11, 9, 8), calendar: cal)
                && !overdue.isOverdue(now: date(2026, 11, 8, 23), calendar: cal))

        // MARK: Reminders

        let allDayReminder = ReminderSchedule.fireDate(occurrenceStart: date(2026, 11, 20), isAllDay: true,
                                                       offset: .day1, calendar: cal)
        check("All-day reminder fires 9 AM the day before",
              key(allDayReminder) == "2026-11-19" && hm(allDayReminder) == "09:00",
              "got \(key(allDayReminder)) \(hm(allDayReminder))")

        // MARK: Money

        let parsed = ["12", "12.5", "$1,234.56", "0.999", "abc", ""].map { Money.parseInput($0) }
        check("Amount input parsing", parsed == [1200, 1250, 123_456, 100, nil, nil], "got \(parsed)")
        check("Comma-decimal amounts", Money.parseInput("12,50", decimalSeparator: ",") == 1250)
        let found = Money.amounts(in: "Dues are $35, plus $1,200.50 for camp and 20 dollars for the shirt.").map(\.cents)
        check("Finds dollar amounts in text", found == [3500, 120_050, 2000], "got \(found)")
        check("Plain amount formatting", Money.plain(123_405) == "1234.05" && Money.plain(-5) == "-0.05")

        // MARK: Messages

        let extractor = MessageExtractor(detector: detector, calendar: cal, now: date(2026, 11, 9, 8),
                                         members: [FamilyMember(name: "Maya", role: .child, color: .purple)])
        let sentences = MessageExtractor.sentences(in: "Dr. Patel's office called. Picture day is Nov. 13! Pickup is at 3 p.m. Please be on time.\n• Bring a water bottle")
        check("Splits sentences without breaking “Dr.”, “Nov.” or “p.m.”",
              sentences == ["Dr. Patel's office called.", "Picture day is Nov. 13!", "Pickup is at 3 p.m.",
                            "Please be on time.", "Bring a water bottle"], "got \(sentences)")

        let picture = extractor.suggestions(for: "Reminder: Picture day is Thursday, November 12!")
        let pictureEvent = picture.first { $0.kind == .event }
        check("“Picture day is …” becomes an all-day event",
              pictureEvent?.title == "Picture day" && pictureEvent?.isAllDay == true && key(pictureEvent?.date).hasSuffix("-11-12"),
              "got \(picture.map { "\($0.kind) \($0.title) \(key($0.date))" })")

        let slip = extractor.suggestions(for: "Please return Maya's signed permission slip by Friday, November 13.")
        let slipTask = slip.first { $0.kind == .task }
        check("“Return … by Friday” becomes a to-do due that day",
              slipTask?.title == "Return Maya's signed permission slip" && key(slipTask?.date).hasSuffix("-11-13")
                && !slip.contains { $0.kind == .event },
              "got \(slip.map { "\($0.kind) \($0.title) \(key($0.date))" })")
        check("Names in a message tag that child", slipTask?.memberIDs.count == 1)

        let concert = extractor.suggestions(for: "The winter concert will be on December 10 at 6:30 PM in the gym.")
        let concertEvent = concert.first { $0.kind == .event }
        check("Timed event keeps its time",
              concertEvent?.title == "Winter concert in the gym" && concertEvent?.isAllDay == false
                && key(concertEvent?.date).hasSuffix("-12-10") && hm(concertEvent?.date) == "18:30",
              "got \(concert.map { "\($0.kind) \($0.title) \(key($0.date)) \(hm($0.date))" })")

        let fee = extractor.suggestions(for: "The field trip to the zoo costs $12, due by November 20.")
        let feeExpense = fee.first { $0.kind == .expense }
        let feeTask = fee.first { $0.kind == .task }
        check("A fee becomes an expense and a to-pay task",
              feeExpense?.amountCents == 1200 && feeExpense?.expenseCategory == .school
                && feeTask?.title == "Pay for field trip to the zoo" && key(feeTask?.date).hasSuffix("-11-20"),
              "got \(fee.map { "\($0.kind) \($0.title) \($0.amountCents ?? 0) \($0.expenseCategory) \(key($0.date))" })")

        let dues = extractor.suggestions(for: "Team dues are $35 — please pay by November 16.")
        check("Clause after a dash is dropped from titles",
              dues.contains { $0.kind == .task && $0.title == "Pay for team dues" }
                && dues.contains { $0.kind == .expense && $0.title == "Team dues" && $0.expenseCategory == .activities },
              "got \(dues.map { "\($0.kind) \($0.title) \($0.expenseCategory)" })")

        let flyerText = MessageExtractor.reflow(["SPRING PICTURE DAY", "Friday, November 13", "Order your package online",
                                                 "by November 10. Retakes will be", "on December 2."])
        check("Photo text: wrapped lines rejoin, headings stay separate",
              flyerText == "SPRING PICTURE DAY\nFriday, November 13\nOrder your package online by November 10. Retakes will be on December 2.",
              "got \(flyerText.debugDescription)")
        let flyer = extractor.suggestions(for: flyerText)
        check("Flyer heading names the event on the next line's date",
              flyer.contains { $0.kind == .event && $0.title == "Spring Picture Day" && key($0.date).hasSuffix("-11-13") }
                && flyer.contains { $0.kind == .task && $0.title == "Order your package online" && key($0.date).hasSuffix("-11-10") },
              "got \(flyer.map { "\($0.kind) \($0.title) \(key($0.date))" })")

        var inbox = FamilyData()
        var message = InboxMessage(body: "x")
        message.suggestions = picture + slip
        inbox.messages = [message]
        for s in message.suggestions {
            inbox.accept(suggestionID: s.id, inMessage: message.id, calendar: cal, now: date(2026, 11, 9, 8))
        }
        let madeEvent = inbox.events.first
        check("Accepting suggestions creates linked items and files the message",
              inbox.events.count == 1 && inbox.tasks.count == 1 && inbox.messages[0].status == .done
                && madeEvent?.sourceMessageID == message.id && madeEvent?.isAllDay == true
                && madeEvent.map { $0.start == $0.end } == true && inbox.tasks[0].remind,
              "events \(inbox.events.count) tasks \(inbox.tasks.count) status \(inbox.messages[0].status)")

        let undated = extractor.suggestions(for: "Please bring a change of clothes in a labeled bag.")
        check("A request without a date is still a to-do",
              undated.count == 1 && undated.first?.kind == .task && undated.first?.date == nil
                && undated.first?.title == "Bring a change of clothes in a labeled bag",
              "got \(undated.map { "\($0.kind) \($0.title)" })")

        let chatter = extractor.suggestions(for: "Thanks so much for a wonderful year! The kids had fun.")
        check("Plain chatter suggests nothing", chatter.isEmpty, "got \(chatter.map(\.title))")

        // MARK: File formats

        let ics = ICSExporter.calendar([soccer, trip], members: [], calendar: cal, now: date(2026, 11, 9))
        check("Calendar export has repeat rule and all-day dates",
              ics.contains("RRULE:FREQ=WEEKLY;BYDAY=MO,WE") && ics.contains("DTSTART;VALUE=DATE:20261120")
                && ics.contains("DTEND;VALUE=DATE:20261124") && ics.contains("DTSTART;TZID=America/New_York:20261102T173000"))
        let folded = ICSExporter.fold("DESCRIPTION:" + String(repeating: "é", count: 60))
        check("Long calendar lines fold at 75 bytes",
              folded.components(separatedBy: "\r\n").allSatisfy { $0.utf8.count <= 75 })
        check("Calendar text escaping", ICSExporter.escape("Snacks; juice, water\nThanks") == "Snacks\\; juice\\, water\\nThanks")

        let csv = CSVExporter.encode([["Name", "Note"], ["Shoes, \"red\"", "=SUM(A1)"]])
        check("CSV quoting and formula guard", csv == "Name,Note\r\n\"Shoes, \"\"red\"\"\",'=SUM(A1)\r\n", "got \(csv)")

        // MARK: Saving

        let full = SampleData.make(now: date(2026, 11, 9, 14), calendar: cal, detector: detector)
        do {
            let encoded = try FamilyData.encoder().encode(full)
            let decoded = try FamilyData.decoder().decode(FamilyData.self, from: encoded)
            check("Save file round-trips", decoded == full)
            let old = try FamilyData.decoder().decode(FamilyData.self, from: Data(#"{"members":[]}"#.utf8))
            check("Older save files without newer sections still open", old.isEmpty)
        } catch {
            check("Save file round-trips", false, "\(error)")
        }
        check("Sample family has messages with suggestions",
              full.messages.first.map { $0.suggestions.count >= 4 } ?? false,
              "got \(full.messages.first?.suggestions.map { "\($0.kind) \($0.title)" } ?? [])")

        return results
    }
}
