import Foundation

/// A made-up family, placed around today's date, for trying Kinboard out before typing
/// in your own. Loading it replaces whatever is in the app (Settings asks first).
enum SampleData {
    static func make(now: Date, calendar: Calendar, detector: DateDetecting) -> FamilyData {
        var d = FamilyData()
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        func at(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day(offset))!
        }
        func yearsAgo(_ years: Int, months: Int = 0) -> Date {
            calendar.date(byAdding: DateComponents(year: -years, month: -months, day: -9), to: today)!
        }
        /// Next date (from tomorrow on) that falls on the given weekday.
        func next(_ weekday: Int) -> Int {
            let current = calendar.component(.weekday, from: today)
            let diff = (weekday - current + 7) % 7
            return diff == 0 ? 7 : diff
        }

        let alex = FamilyMember(name: "Alex Rivera", role: .parent, color: .blue)
        let jordan = FamilyMember(name: "Jordan Rivera", role: .parent, color: .green)
        let maya = FamilyMember(name: "Maya", role: .child, color: .purple, birthday: yearsAgo(8, months: -1))
        let leo = FamilyMember(name: "Leo", role: .child, color: .orange, birthday: yearsAgo(5, months: 3))
        let nora = FamilyMember(name: "Nora", role: .child, color: .pink, birthday: yearsAgo(0, months: 7))
        d.members = [alex, jordan, maya, leo, nora]

        // Calendar
        d.events = [
            FamilyEvent(title: "Soccer practice", start: at(-14, 17, 30), end: at(-14, 18, 30),
                        location: "Riverside Park, Field 3", area: .activities, memberIDs: [maya.id],
                        repeatRule: RepeatRule(frequency: .weekly, weekdays: [3, 5]), reminder: .hour1),
            FamilyEvent(title: "Swim lessons", start: at(-21 + next(7), 9, 0), end: at(-21 + next(7), 9, 45),
                        location: "YMCA pool", area: .activities, memberIDs: [leo.id],
                        repeatRule: RepeatRule(frequency: .weekly), reminder: .hour1),
            FamilyEvent(title: "Nora — 9-month checkup", start: at(6, 10, 15), end: at(6, 11, 0),
                        location: "Lakeside Pediatrics", notes: "Bring the vaccine card.",
                        area: .medical, memberIDs: [nora.id, jordan.id], reminder: .day1),
            FamilyEvent(title: "Parent-teacher conference", start: at(9, 15, 40), end: at(9, 16, 0),
                        location: "Room 14", area: .school, memberIDs: [maya.id, alex.id], reminder: .hours2),
            FamilyEvent(title: "Grandma visiting", start: day(12), end: day(15), isAllDay: true,
                        area: .social, memberIDs: [], reminder: .none),
            FamilyEvent(title: "Library books due", start: day(2), end: day(2), isAllDay: true,
                        area: .school, memberIDs: [leo.id], repeatRule: RepeatRule(frequency: .weekly, interval: 2)),
        ]

        // Tasks
        d.tasks = [
            TaskItem(title: "Buy Leo new sneakers", dueDate: day(3), area: .household,
                     assigneeID: jordan.id, memberIDs: [leo.id], createdAt: day(-3)),
            TaskItem(title: "Schedule dentist cleanings", notes: "Both big kids are due.", area: .medical,
                     assigneeID: alex.id, memberIDs: [maya.id, leo.id], createdAt: day(-6)),
            TaskItem(title: "Order more formula", dueDate: day(-1), area: .childcare, assigneeID: alex.id,
                     memberIDs: [nora.id], isFlagged: true, createdAt: day(-4)),
            TaskItem(title: "Piano practice (15 min)", dueDate: day(0), area: .activities, assigneeID: maya.id,
                     memberIDs: [maya.id], repeatRule: RepeatRule(frequency: .daily), createdAt: day(-30)),
            TaskItem(title: "Pack Leo's swim bag", dueDate: at(next(7) - 1, 19, 0), hasDueTime: true,
                     area: .activities, assigneeID: jordan.id, memberIDs: [leo.id],
                     repeatRule: RepeatRule(frequency: .weekly), remind: true, createdAt: day(-20)),
            TaskItem(title: "Put recycling out", dueDate: day(next(4)), area: .household, assigneeID: maya.id,
                     repeatRule: RepeatRule(frequency: .weekly), createdAt: day(-40)),
            TaskItem(title: "Return holiday sweater", area: .household, createdAt: day(-10),
                     completedAt: day(-2)),
        ]

        // Spending: this month and the two before, so the trend chart has a shape.
        var expenses: [Expense] = []
        for back in 0...2 {
            let base = calendar.date(byAdding: .month, value: -back, to: calendar.dateInterval(of: .month, for: today)!.start)!
            func inMonth(_ dayOfMonth: Int) -> Date {
                let date = calendar.date(byAdding: .day, value: dayOfMonth - 1, to: base)!
                return min(date, today)
            }
            expenses.append(Expense(title: "Little Sprouts daycare", amountCents: 145_000, date: inMonth(1),
                                    category: .childcare, memberIDs: [nora.id], paidByID: alex.id,
                                    reimbursement: back == 0 ? .toSubmit : .reimbursed,
                                    notes: "Dependent care FSA"))
            expenses.append(Expense(title: "Diapers & wipes", amountCents: 4_250 + back * 310, date: inMonth(4),
                                    category: .babySupplies, memberIDs: [nora.id], paidByID: jordan.id))
            expenses.append(Expense(title: "School lunch account", amountCents: 4_000, date: inMonth(6),
                                    category: .food, memberIDs: [maya.id], paidByID: alex.id))
        }
        expenses += [
            Expense(title: "Soccer league registration", amountCents: 12_000, date: day(-40),
                    category: .activities, memberIDs: [maya.id], paidByID: alex.id),
            Expense(title: "Sneakers", amountCents: 5_499, date: day(-1), category: .clothing,
                    memberIDs: [maya.id], paidByID: jordan.id),
            Expense(title: "Pediatrician copay", amountCents: 3_000, date: day(-2), category: .medical,
                    memberIDs: [leo.id], paidByID: jordan.id, reimbursement: .toSubmit, notes: "HSA"),
            Expense(title: "Book fair", amountCents: 1_800, date: day(-3), category: .toys,
                    memberIDs: [maya.id], paidByID: alex.id),
            Expense(title: "Birthday gift for Sam's party", amountCents: 2_500, date: day(-5), category: .gifts,
                    memberIDs: [leo.id], paidByID: jordan.id),
        ]
        d.expenses = expenses
        d.budgets = [
            Expense.Category.childcare.rawValue: 150_000,
            Expense.Category.babySupplies.rawValue: 12_000,
            Expense.Category.activities.rawValue: 20_000,
            Expense.Category.clothing.rawValue: 10_000,
            Expense.Category.medical.rawValue: 10_000,
            Expense.Category.school.rawValue: 7_500,
            Expense.Category.food.rawValue: 8_000,
            Expense.Category.gifts.rawValue: 6_000,
        ]

        // Trackers
        let bottle = Tracker(name: "Bottle", symbol: "drop", kind: .quantity, unit: "oz", memberID: nora.id, color: .pink)
        let diaper = Tracker(name: "Diaper", symbol: "circle.dashed", kind: .event, memberID: nora.id, color: .teal)
        let sleep = Tracker(name: "Sleep", symbol: "moon.zzz", kind: .duration, memberID: nora.id, color: .indigo)
        let weight = Tracker(name: "Weight", symbol: "scalemass", kind: .quantity, unit: "lb", memberID: nora.id,
                             color: .green, isPinned: false)
        let reading = Tracker(name: "Reading", symbol: "book", kind: .quantity, unit: "min", memberID: maya.id, color: .purple)
        d.trackers = [bottle, diaper, sleep, weight, reading]
        var entries: [TrackerEntry] = []
        for (h, oz) in [(6, 5.0), (9, 4.5), (12, 5.0), (15, 4.0)] where at(0, h) <= now {
            entries.append(TrackerEntry(trackerID: bottle.id, date: at(0, h, 10), value: oz))
        }
        for (h, oz) in [(6, 5.0), (9, 5.0), (12, 4.5), (15, 5.0), (18, 4.0), (21, 6.0)] {
            entries.append(TrackerEntry(trackerID: bottle.id, date: at(-1, h, 5), value: oz))
        }
        for h in [7, 10, 13] where at(0, h) <= now {
            entries.append(TrackerEntry(trackerID: diaper.id, date: at(0, h, 30), note: "Wet"))
        }
        entries.append(TrackerEntry(trackerID: sleep.id, date: at(-1, 19, 30), endDate: at(0, 5, 45), note: "Night"))
        if at(0, 13) <= now {
            entries.append(TrackerEntry(trackerID: sleep.id, date: at(0, 9, 40), endDate: at(0, 11, 5), note: "Nap"))
        }
        for (monthsBack, lb) in [(6, 9.8), (5, 11.6), (4, 13.1), (3, 14.4), (2, 15.6), (1, 16.5), (0, 17.3)] {
            let date = calendar.date(byAdding: .month, value: -monthsBack, to: day(-3))!
            entries.append(TrackerEntry(trackerID: weight.id, date: date, value: lb))
        }
        for back in 1...10 {
            entries.append(TrackerEntry(trackerID: reading.id, date: at(-back, 20), value: Double([15, 20, 25, 30][back % 4])))
        }
        d.trackerEntries = entries

        // People and facts
        d.contacts = [
            Contact(name: "Dr. Priya Shah", role: "Pediatrician", phone: "(555) 014-2290",
                    email: "frontdesk@lakeside-peds.example", memberIDs: [maya.id, leo.id, nora.id],
                    notes: "Lakeside Pediatrics. Nurse line after hours: (555) 014-2299"),
            Contact(name: "Ms. Alvarez", role: "2nd grade teacher", email: "alvarez@lincoln-elem.example",
                    memberIDs: [maya.id]),
            Contact(name: "Coach Dan", role: "Soccer coach", phone: "(555) 018-7741", memberIDs: [maya.id]),
            Contact(name: "Sam Okafor", role: "Babysitter", phone: "(555) 012-3344",
                    notes: "Available weekday evenings. $20/hr."),
        ]
        d.info = [
            InfoItem(memberID: maya.id, category: .medical, title: "Allergies", value: "Peanuts — EpiPen in backpack"),
            InfoItem(memberID: maya.id, category: .school, title: "School", value: "Lincoln Elementary · 2nd grade · Room 14"),
            InfoItem(memberID: maya.id, category: .sizes, title: "Shoes", value: "Youth 2"),
            InfoItem(memberID: leo.id, category: .sizes, title: "Shoes", value: "Toddler 12"),
            InfoItem(memberID: leo.id, category: .sizes, title: "Clothes", value: "5T"),
            InfoItem(memberID: nora.id, category: .medical, title: "Formula", value: "Sensitive, powder"),
            InfoItem(memberID: nil, category: .insurance, title: "Health insurance", value: "Member ID XJH-000-000 · Group 4471"),
        ]

        // Messages, with suggestions pulled out the same way a pasted message would be.
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.timeZone = calendar.timeZone
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "EEEE, MMMM d"
        let school = """
            Hi Lincoln families!
            Picture day is \(fmt.string(from: day(4))). Please send in the order form if you'd like prints.
            Please return the signed field trip permission slip by \(fmt.string(from: day(5))).
            The field trip to the science museum costs $12, due by \(fmt.string(from: day(8))).
            Our winter concert will be on \(fmt.string(from: day(16))) at 6:30 PM in the gym.
            Thanks, Ms. Alvarez
            """
        let coach = """
            Reminder: tournament is \(fmt.string(from: day(10))) at 8:00 AM, arrive 30 minutes early.
            Team dues are $35 — please pay by \(fmt.string(from: day(7))).
            """
        let extractor = MessageExtractor(detector: detector, calendar: calendar, now: now, members: d.members)
        var m1 = InboxMessage(receivedAt: at(0, 7, 45), sender: "Ms. Alvarez", subject: "Picture day, field trip and concert",
                              body: school, source: .school, memberIDs: [maya.id])
        m1.suggestions = extractor.suggestions(for: school, defaultMemberIDs: [maya.id])
        var m2 = InboxMessage(receivedAt: at(-1, 20, 12), sender: "Coach Dan", subject: "",
                              body: coach, source: .activities, memberIDs: [maya.id])
        m2.suggestions = extractor.suggestions(for: coach, defaultMemberIDs: [maya.id])
        let m3 = InboxMessage(receivedAt: at(-3, 12, 0), sender: "Little Sprouts", subject: "Nora's day",
                              body: "Nora had a great day! She napped 1h 20m and finished both bottles. We're running low on diapers — please bring a new pack.",
                              source: .daycare, memberIDs: [nora.id], status: .done)
        d.messages = [m1, m2, m3]
        return d
    }
}
