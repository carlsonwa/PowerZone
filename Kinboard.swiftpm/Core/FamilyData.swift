import Foundation

/// The whole family's data as one value. It's saved as a single JSON file — a family
/// produces thousands of records, not millions, so one file keeps saving atomic and makes
/// a backup a plain copy.
struct FamilyData: Codable, Equatable {
    static let currentVersion = 1

    var version = FamilyData.currentVersion
    var members: [FamilyMember] = []
    var events: [FamilyEvent] = []
    var tasks: [TaskItem] = []
    var expenses: [Expense] = []
    /// Monthly budget per spending category, in cents. Missing means no budget.
    var budgets: [String: Int] = [:]
    var trackers: [Tracker] = []
    var trackerEntries: [TrackerEntry] = []
    var messages: [InboxMessage] = []
    var contacts: [Contact] = []
    var info: [InfoItem] = []

    init() {}

    // Decode field by field with defaults, so a backup from an older version that lacks a
    // newer collection still opens instead of failing outright.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        members = try c.decodeIfPresent([FamilyMember].self, forKey: .members) ?? []
        events = try c.decodeIfPresent([FamilyEvent].self, forKey: .events) ?? []
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        expenses = try c.decodeIfPresent([Expense].self, forKey: .expenses) ?? []
        budgets = try c.decodeIfPresent([String: Int].self, forKey: .budgets) ?? [:]
        trackers = try c.decodeIfPresent([Tracker].self, forKey: .trackers) ?? []
        trackerEntries = try c.decodeIfPresent([TrackerEntry].self, forKey: .trackerEntries) ?? []
        messages = try c.decodeIfPresent([InboxMessage].self, forKey: .messages) ?? []
        contacts = try c.decodeIfPresent([Contact].self, forKey: .contacts) ?? []
        info = try c.decodeIfPresent([InfoItem].self, forKey: .info) ?? []
    }

    var isEmpty: Bool {
        members.isEmpty && events.isEmpty && tasks.isEmpty && expenses.isEmpty
            && trackers.isEmpty && messages.isEmpty && contacts.isEmpty && info.isEmpty
    }

    // MARK: Encoding

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: Lookups

    func member(_ id: UUID?) -> FamilyMember? {
        guard let id else { return nil }
        return members.first { $0.id == id }
    }

    func members(_ ids: [UUID]) -> [FamilyMember] {
        ids.compactMap { id in members.first { $0.id == id } }
    }

    var children: [FamilyMember] { members.filter { $0.role == .child } }
    var adults: [FamilyMember] { members.filter { $0.role != .child } }

    func tracker(_ id: UUID) -> Tracker? { trackers.first { $0.id == id } }

    // MARK: Calendar queries

    func occurrences(from: Date, to: Date, calendar: Calendar, memberID: UUID? = nil) -> [EventOccurrence] {
        events
            .filter { memberID == nil || $0.memberIDs.contains(memberID!) }
            .flatMap { $0.occurrences(from: from, to: to, calendar: calendar) }
            .sorted { lhs, rhs in
                // All-day items lead the day, then by time, then by title for stability.
                if lhs.event.isAllDay != rhs.event.isAllDay { return lhs.event.isAllDay }
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                return lhs.event.title < rhs.event.title
            }
    }

    func occurrences(on day: Date, calendar: Calendar, memberID: UUID? = nil) -> [EventOccurrence] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return occurrences(from: start, to: end, calendar: calendar, memberID: memberID)
    }

    /// Days in `[from, to)` that have at least one event, as day keys — drives the dots
    /// on the month grid.
    func busyDays(from: Date, to: Date, calendar: Calendar) -> [String: [PaletteColor]] {
        var result: [String: [PaletteColor]] = [:]
        for occ in occurrences(from: from, to: to, calendar: calendar) {
            let color = member(occ.event.memberIDs.first)?.color ?? .gray
            var day = max(calendar.startOfDay(for: occ.start), calendar.startOfDay(for: from))
            let last = occ.event.isAllDay ? occ.end.addingTimeInterval(-1) : max(occ.start, occ.end.addingTimeInterval(-1))
            while day <= last && day < to {
                let key = DayKey.make(day, calendar: calendar)
                if !(result[key] ?? []).contains(color) { result[key, default: []].append(color) }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return result
    }

    /// Upcoming birthdays as (member, next birthday date, age they'll turn).
    func upcomingBirthdays(within days: Int, from now: Date, calendar: Calendar) -> [(FamilyMember, Date, Int)] {
        let today = calendar.startOfDay(for: now)
        guard let horizon = calendar.date(byAdding: .day, value: days, to: today) else { return [] }
        return members.compactMap { m -> (FamilyMember, Date, Int)? in
            guard let birthday = m.birthday,
                  let next = Recurrence.firstStart(seriesStart: calendar.startOfDay(for: birthday),
                                                   rule: RepeatRule(frequency: .yearly),
                                                   calendar: calendar, onOrAfter: today),
                  next < horizon else { return nil }
            let age = calendar.dateComponents([.year], from: birthday, to: next).year ?? 0
            return (m, next, age)
        }
        .sorted { $0.1 < $1.1 }
    }

    // MARK: Task queries

    func openTasks() -> [TaskItem] {
        tasks.filter { !$0.isDone }.sorted(by: TaskItem.dueOrder)
    }

    func overdueTasks(now: Date, calendar: Calendar) -> [TaskItem] {
        openTasks().filter { $0.isOverdue(now: now, calendar: calendar) }
    }

    func tasksDue(on day: Date, calendar: Calendar) -> [TaskItem] {
        openTasks().filter { t in t.dueDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
    }

    // MARK: Spending queries

    func expenses(inMonthOf date: Date, calendar: Calendar) -> [Expense] {
        guard let month = calendar.dateInterval(of: .month, for: date) else { return [] }
        return expenses.filter { month.start <= $0.date && $0.date < month.end }
    }

    func totalCents(_ list: [Expense]) -> Int { list.reduce(0) { $0 + $1.amountCents } }

    /// Spending per category for the month containing `date`, largest first.
    func categoryTotals(inMonthOf date: Date, calendar: Calendar) -> [(Expense.Category, Int)] {
        var totals: [Expense.Category: Int] = [:]
        for e in expenses(inMonthOf: date, calendar: calendar) { totals[e.category, default: 0] += e.amountCents }
        return totals.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.label < $1.key.label }
            .map { ($0.key, $0.value) }
    }

    /// Totals for each of the last `count` months ending with the month of `date`, oldest first.
    func monthlyTotals(endingAt date: Date, count: Int, calendar: Calendar) -> [(Date, Int)] {
        guard let thisMonth = calendar.dateInterval(of: .month, for: date)?.start else { return [] }
        return (0..<count).reversed().compactMap { back -> (Date, Int)? in
            guard let month = calendar.date(byAdding: .month, value: -back, to: thisMonth) else { return nil }
            return (month, totalCents(expenses(inMonthOf: month, calendar: calendar)))
        }
    }

    var totalBudgetCents: Int { budgets.values.reduce(0, +) }

    func budgetCents(for category: Expense.Category) -> Int? { budgets[category.rawValue] }

    /// Money spent on reimbursable items that hasn't come back yet.
    var pendingReimbursementCents: Int {
        expenses.filter { $0.reimbursement == .toSubmit || $0.reimbursement == .submitted }
            .reduce(0) { $0 + $1.amountCents }
    }

    // MARK: Tracker queries

    func entries(for trackerID: UUID) -> [TrackerEntry] {
        trackerEntries.filter { $0.trackerID == trackerID }.sorted { $0.date > $1.date }
    }

    func lastEntry(for trackerID: UUID) -> TrackerEntry? {
        trackerEntries.filter { $0.trackerID == trackerID }.max { $0.date < $1.date }
    }

    func runningEntry(for trackerID: UUID) -> TrackerEntry? {
        trackerEntries.first { $0.trackerID == trackerID && $0.endDate == nil }
            .flatMap { tracker(trackerID)?.kind == .duration ? $0 : nil }
    }

    /// Today's count / sum / total time for a tracker, depending on its kind.
    func todaySummary(for tracker: Tracker, now: Date, calendar: Calendar) -> (count: Int, total: Double) {
        let today = trackerEntries.filter { $0.trackerID == tracker.id && calendar.isDate($0.date, inSameDayAs: now) }
        switch tracker.kind {
        case .event: return (today.count, Double(today.count))
        case .quantity: return (today.count, today.compactMap(\.value).reduce(0, +))
        case .duration:
            let seconds = today.reduce(0.0) { sum, e in sum + (e.endDate ?? now).timeIntervalSince(e.date) }
            return (today.count, seconds)
        }
    }

    // MARK: Inbox queries

    var messagesNeedingReview: [InboxMessage] {
        messages.filter { $0.status == .needsReview }.sorted { $0.receivedAt > $1.receivedAt }
    }

    // MARK: Mutations shared by the store and the checks

    mutating func completeTask(id: UUID, at date: Date, calendar: Calendar) {
        guard let i = tasks.firstIndex(where: { $0.id == id }), !tasks[i].isDone else { return }
        tasks[i].completedAt = date
        if let next = tasks[i].nextInstance(completedOn: date, calendar: calendar) {
            tasks.append(next)
        }
    }

    mutating func reopenTask(id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].completedAt = nil
    }

    /// Removes a single occurrence of a repeating event, or the whole event if it doesn't repeat.
    mutating func deleteOccurrence(_ occurrence: EventOccurrence, calendar: Calendar) {
        guard let i = events.firstIndex(where: { $0.id == occurrence.event.id }) else { return }
        if events[i].repeatRule == nil {
            events.remove(at: i)
        } else {
            events[i].skippedDays.append(DayKey.make(occurrence.start, calendar: calendar))
        }
    }

    /// Deletes a member and scrubs every reference to them.
    mutating func deleteMember(id: UUID) {
        members.removeAll { $0.id == id }
        for i in events.indices { events[i].memberIDs.removeAll { $0 == id } }
        for i in tasks.indices {
            tasks[i].memberIDs.removeAll { $0 == id }
            if tasks[i].assigneeID == id { tasks[i].assigneeID = nil }
        }
        for i in expenses.indices {
            expenses[i].memberIDs.removeAll { $0 == id }
            if expenses[i].paidByID == id { expenses[i].paidByID = nil }
        }
        for i in trackers.indices where trackers[i].memberID == id { trackers[i].memberID = nil }
        for i in messages.indices { messages[i].memberIDs.removeAll { $0 == id } }
        for i in contacts.indices { contacts[i].memberIDs.removeAll { $0 == id } }
        info.removeAll { $0.memberID == id }
    }

    mutating func deleteTracker(id: UUID) {
        trackers.removeAll { $0.id == id }
        trackerEntries.removeAll { $0.trackerID == id }
    }

    /// Everything that was created from a message, for the "added from this message" list.
    func items(fromMessage id: UUID) -> (events: [FamilyEvent], tasks: [TaskItem], expenses: [Expense]) {
        (events.filter { $0.sourceMessageID == id },
         tasks.filter { $0.sourceMessageID == id },
         expenses.filter { $0.sourceMessageID == id })
    }
}

extension TaskItem {
    static func dueOrder(_ a: TaskItem, _ b: TaskItem) -> Bool {
        switch (a.dueDate, b.dueDate) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default:
            if a.isFlagged != b.isFlagged { return a.isFlagged }
            return a.createdAt < b.createdAt
        }
    }

    func isOverdue(now: Date, calendar: Calendar) -> Bool {
        guard !isDone, let due = dueDate else { return false }
        if hasDueTime { return due < now }
        return calendar.startOfDay(for: due) < calendar.startOfDay(for: now)
    }
}
