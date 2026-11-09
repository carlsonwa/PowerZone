import SwiftUI

/// The dashboard: what's happening today, what needs doing, what needs reading, and
/// where the money's going — each card a tap away from the full screen.
struct TodayView: View {
    @EnvironmentObject var store: FamilyStore
    @EnvironmentObject var router: Router
    @State private var sheet: TodaySheet? = nil
    @State private var now = Date()

    enum TodaySheet: Identifiable {
        case event, task, expense, capture
        case log(Tracker)

        var id: String {
            switch self {
            case .event: return "event"
            case .task: return "task"
            case .expense: return "expense"
            case .capture: return "capture"
            case .log(let t): return "log-\(t.id)"
            }
        }
    }

    private var calendar: Calendar { store.calendar }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    if !store.data.members.isEmpty { peopleRow }
                    if !store.data.messagesNeedingReview.isEmpty { inboxCard }
                    scheduleCard
                    tasksCard
                    if !pinnedTrackers.isEmpty { trackersCard }
                    spendingCard
                    comingUpCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        FamilyView()
                    } label: {
                        Label("Family", systemImage: "person.2")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    addMenu
                }
            }
            .sheet(item: $sheet) { which in
                sheetContent(which)
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    now = Date()
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(greeting).font(.title2.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String {
        let hour = calendar.component(.hour, from: now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var addMenu: some View {
        Menu {
            Button { sheet = .capture } label: { Label("Capture a message", systemImage: "tray.and.arrow.down") }
            Button { sheet = .event } label: { Label("New event", systemImage: "calendar.badge.plus") }
            Button { sheet = .task } label: { Label("New to-do", systemImage: "checklist") }
            Button { sheet = .expense } label: { Label("New expense", systemImage: "dollarsign.circle") }
        } label: {
            Image(systemName: "plus.circle.fill").font(.title3)
        }
        .accessibilityLabel("Add")
    }

    @ViewBuilder
    private func sheetContent(_ which: TodaySheet) -> some View {
        switch which {
        case .event:
            EventEditor(original: FamilyEvent.newDraft(on: now, calendar: calendar))
        case .task:
            TaskEditor(original: TaskItem(title: ""))
        case .expense:
            ExpenseEditor(original: Expense(title: "", amountCents: 0, date: now, category: .other))
        case .capture:
            CaptureView { id in router.openMessage(id) }
        case .log(let tracker):
            TrackerLogSheet(tracker: tracker, original: nil)
        }
    }

    // MARK: - People

    private var peopleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(store.data.members) { m in
                    NavigationLink {
                        MemberDetailView(memberID: m.id)
                    } label: {
                        VStack(spacing: 4) {
                            MemberAvatar(member: m, size: 52)
                            Text(m.firstName).font(.caption).foregroundStyle(.primary).lineLimit(1)
                        }
                        .frame(width: 60)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Inbox

    private var inboxCard: some View {
        let messages = store.data.messagesNeedingReview
        return Card(title: messages.count == 1 ? "1 message to review" : "\(messages.count) messages to review",
                    symbol: "tray.full", action: { router.tab = .inbox }, actionLabel: "Inbox") {
            ForEach(messages.prefix(3)) { m in
                Button {
                    router.openMessage(m.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: m.source.symbol)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.displayTitle).lineLimit(1).foregroundStyle(.primary)
                            Text(m.sender.isEmpty ? m.source.label : m.sender)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !m.pendingSuggestions.isEmpty {
                            Text("\(m.pendingSuggestions.count)")
                                .font(.caption.bold())
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.18), in: Capsule())
                        }
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Schedule

    private var scheduleCard: some View {
        let today = store.data.occurrences(on: now, calendar: calendar)
        let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let tomorrow = store.data.occurrences(on: tomorrowDate, calendar: calendar)
        return Card(title: "Schedule", symbol: "calendar", action: { router.tab = .calendar }) {
            if today.isEmpty {
                Text("Nothing on the calendar today.").foregroundStyle(.secondary)
            }
            ForEach(today) { occ in
                NavigationLink {
                    EventDetailView(eventID: occ.event.id, occurrenceStart: occ.start)
                } label: {
                    EventRow(occurrence: occ, members: store.data.members(occ.event.memberIDs), now: now)
                }
                .buttonStyle(.plain)
            }
            if !tomorrow.isEmpty {
                Text("Tomorrow").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
                ForEach(tomorrow.prefix(3)) { occ in
                    NavigationLink {
                        EventDetailView(eventID: occ.event.id, occurrenceStart: occ.start)
                    } label: {
                        EventRow(occurrence: occ, members: store.data.members(occ.event.memberIDs), now: now)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Tasks

    private var dueTasks: [TaskItem] {
        store.data.openTasks().filter { t in
            guard let due = t.dueDate else { return t.isFlagged }
            return calendar.startOfDay(for: due) <= calendar.startOfDay(for: now)
        }
    }

    private var tasksCard: some View {
        let tasks = dueTasks
        let open = store.data.openTasks().count
        return Card(title: "To-dos", symbol: "checklist", action: { router.tab = .tasks }) {
            if tasks.isEmpty {
                Text(open == 0 ? "Nothing to do. Enjoy it." : "Nothing due today. \(open) open in Tasks.")
                    .foregroundStyle(.secondary)
            }
            ForEach(tasks.prefix(6)) { t in
                HStack(spacing: 10) {
                    DoneButton(isDone: t.isDone) {
                        withAnimation { store.toggleDone(t.id) }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).lineLimit(2)
                        if let due = t.dueDate {
                            Text(t.isOverdue(now: now, calendar: calendar) ? "Overdue · \(Fmt.shortDay(due))"
                                 : (t.hasDueTime ? Fmt.time(due) : "Today"))
                                .font(.caption)
                                .foregroundStyle(t.isOverdue(now: now, calendar: calendar) ? Color.red : Color.secondary)
                        }
                    }
                    Spacer()
                    if t.isFlagged { Image(systemName: "flag.fill").foregroundStyle(.orange).font(.caption) }
                    if let who = store.data.member(t.assigneeID) { MemberAvatar(member: who, size: 22) }
                }
            }
            if tasks.count > 6 {
                Text("+\(tasks.count - 6) more").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Trackers

    private var pinnedTrackers: [Tracker] { store.data.trackers.filter(\.isPinned) }

    private var trackersCard: some View {
        Card(title: "Trackers", symbol: "waveform.path.ecg") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(pinnedTrackers) { t in
                    TrackerTile(tracker: t, now: now) {
                        if t.kind == .quantity {
                            sheet = .log(t)
                        } else {
                            withAnimation { store.quickLog(t) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Spending

    private var spendingCard: some View {
        let monthExpenses = store.data.expenses(inMonthOf: now, calendar: calendar)
        let spent = store.data.totalCents(monthExpenses)
        let budget = store.data.totalBudgetCents
        let top = store.data.categoryTotals(inMonthOf: now, calendar: calendar).prefix(3)
        let pending = store.data.pendingReimbursementCents
        return Card(title: "Spending this month", symbol: "chart.bar", action: { router.tab = .spending }) {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.money(spent)).font(.title2.bold()).monospacedDigit()
                if budget > 0 {
                    Text("of \(Fmt.money(budget))").foregroundStyle(.secondary)
                }
            }
            if budget > 0 {
                ProgressView(value: Double(min(spent, budget)), total: Double(budget))
                    .tint(spent > budget ? Color.red : Color.accentColor)
            }
            ForEach(Array(top), id: \.0) { item in
                HStack {
                    Image(systemName: item.0.symbol).foregroundStyle(item.0.tint).frame(width: 22)
                    Text(item.0.label)
                    Spacer()
                    Text(Fmt.money(item.1)).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
            if pending > 0 {
                Label("\(Fmt.money(pending)) waiting to be reimbursed", systemImage: "arrow.uturn.backward.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Coming up

    private var comingUpCard: some View {
        let start = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now)) ?? now
        let end = calendar.date(byAdding: .day, value: 8, to: calendar.startOfDay(for: now)) ?? now
        let upcoming = store.data.occurrences(from: start, to: end, calendar: calendar)
        let birthdays = store.data.upcomingBirthdays(within: 45, from: now, calendar: calendar)
        return Card(title: "Coming up", symbol: "sparkles") {
            if upcoming.isEmpty && birthdays.isEmpty {
                Text("A quiet week ahead.").foregroundStyle(.secondary)
            }
            ForEach(upcoming.prefix(6)) { occ in
                NavigationLink {
                    EventDetailView(eventID: occ.event.id, occurrenceStart: occ.start)
                } label: {
                    HStack {
                        Text(Fmt.shortDay(occ.start))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 78, alignment: .leading)
                        Text(occ.event.title).lineLimit(1)
                        Spacer()
                        MemberStack(members: store.data.members(occ.event.memberIDs), size: 18)
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.plain)
            }
            ForEach(birthdays, id: \.0.id) { item in
                HStack {
                    Text(Fmt.shortDay(item.1))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 78, alignment: .leading)
                    Image(systemName: "birthday.cake").foregroundStyle(.pink)
                    Text("\(item.0.firstName) turns \(item.2)").lineLimit(1)
                    Spacer()
                }
                .font(.subheadline)
            }
        }
    }
}

// MARK: - Rows used on several screens

struct EventRow: View {
    let occurrence: EventOccurrence
    let members: [FamilyMember]
    var now = Date()

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(members.first?.color.color ?? occurrence.event.area.tint)
                .frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(occurrence.event.title).lineLimit(1).foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Text(Fmt.eventTime(occurrence))
                    if !occurrence.event.location.isEmpty {
                        Text("· \(occurrence.event.location)").lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(isPast ? Color.secondary.opacity(0.6) : Color.secondary)
            }
            Spacer()
            if occurrence.event.repeatRule != nil {
                Image(systemName: "repeat").font(.caption2).foregroundStyle(.tertiary)
            }
            MemberStack(members: members)
        }
        .contentShape(Rectangle())
        .opacity(isPast ? 0.6 : 1)
    }

    private var isPast: Bool { !occurrence.event.isAllDay && occurrence.end < now }
}

struct TrackerTile: View {
    @EnvironmentObject var store: FamilyStore
    let tracker: Tracker
    let now: Date
    let log: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink {
                TrackerDetailView(trackerID: tracker.id)
            } label: {
                HStack(alignment: .top) {
                    Image(systemName: tracker.symbol)
                        .foregroundStyle(tracker.color.color)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tracker.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if let m = store.data.member(tracker.memberID) { MemberAvatar(member: m, size: 20) }
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            Button(action: log) {
                Text(buttonTitle)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(running != nil ? Color.red : tracker.color.color)
        }
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var running: TrackerEntry? { store.data.runningEntry(for: tracker.id) }

    private var buttonTitle: String {
        switch tracker.kind {
        case .event: return "Log now"
        case .quantity: return "Log…"
        case .duration: return running == nil ? "Start" : "Stop"
        }
    }

    private var status: String {
        if let running {
            return "Started \(Fmt.ago(running.date, now: now)) · \(Fmt.duration(now.timeIntervalSince(running.date)))"
        }
        let today = store.data.todaySummary(for: tracker, now: now, calendar: store.calendar)
        let last = store.data.lastEntry(for: tracker.id).map { "Last \(Fmt.ago($0.date, now: now))" } ?? "Nothing logged yet"
        switch tracker.kind {
        case .event:
            return today.count > 0 ? "\(today.count) today · \(last)" : last
        case .quantity:
            return today.count > 0 ? "\(Fmt.number(today.total)) \(tracker.unit) today · \(last)" : last
        case .duration:
            return today.total > 0 ? "\(Fmt.duration(today.total)) today · \(last)" : last
        }
    }
}

extension FamilyEvent {
    /// A new one-hour event starting at the next whole hour of the given day.
    static func newDraft(on day: Date, calendar: Calendar, now: Date = Date()) -> FamilyEvent {
        let hour = calendar.isDate(day, inSameDayAs: now) ? min(calendar.component(.hour, from: now) + 1, 23) : 9
        let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        return FamilyEvent(title: "", start: start, end: start.addingTimeInterval(3600))
    }
}
