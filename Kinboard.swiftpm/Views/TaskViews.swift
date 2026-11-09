import SwiftUI

struct TasksView: View {
    @EnvironmentObject var store: FamilyStore
    @State private var quickTitle = ""
    @State private var editing: TaskItem? = nil
    @State private var memberFilter: UUID? = nil
    @State private var showDone = false
    @State private var search = ""
    @FocusState var quickFocused: Bool

    private var calendar: Calendar { store.calendar }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                        TextField("Add a to-do", text: $quickTitle)
                            .focused($quickFocused)
                            .submitLabel(.done)
                            .onSubmit(addQuick)
                    }
                }

                ForEach(groups, id: \.title) { group in
                    Section {
                        ForEach(group.tasks) { t in
                            TaskRow(task: t) { editing = t }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        store.deleteTask(t.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        store.toggleFlag(t.id)
                                    } label: {
                                        Label(t.isFlagged ? "Unflag" : "Flag", systemImage: "flag")
                                    }
                                    .tint(.orange)
                                }
                        }
                    } header: {
                        Text(group.title)
                            .foregroundStyle(group.title == "Overdue" ? Color.red : Color.secondary)
                    }
                }

                if groups.isEmpty && search.isEmpty {
                    Section {
                        Text("Nothing to do.").foregroundStyle(.secondary)
                    }
                }

                if showDone {
                    Section("Completed") {
                        ForEach(completed) { t in
                            TaskRow(task: t) { editing = t }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        store.deleteTask(t.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("To-dos")
            .searchable(text: $search, prompt: "Search to-dos")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Picker("Person", selection: $memberFilter) {
                            Text("Everyone").tag(UUID?.none)
                            ForEach(store.data.members) { m in
                                Text(m.name).tag(UUID?.some(m.id))
                            }
                        }
                        Toggle("Show completed", isOn: $showDone)
                    } label: {
                        Image(systemName: memberFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Filter")
                    Button {
                        editing = TaskItem(title: "", assigneeID: nil, memberIDs: memberFilter.map { [$0] } ?? [])
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New to-do")
                }
            }
            .sheet(item: $editing) { task in
                TaskEditor(original: task)
            }
        }
    }

    private func matches(_ t: TaskItem) -> Bool {
        if let memberFilter, t.assigneeID != memberFilter, !t.memberIDs.contains(memberFilter) { return false }
        if !search.isEmpty {
            return t.title.localizedCaseInsensitiveContains(search) || t.notes.localizedCaseInsensitiveContains(search)
        }
        return true
    }

    struct DueGroup {
        let title: String
        let tasks: [TaskItem]
    }

    private var groups: [DueGroup] {
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let weekOut = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        let open = store.data.openTasks().filter(matches)

        var overdue: [TaskItem] = [], dueToday: [TaskItem] = [], dueTomorrow: [TaskItem] = []
        var thisWeek: [TaskItem] = [], later: [TaskItem] = [], undated: [TaskItem] = []
        for t in open {
            guard let due = t.dueDate else { undated.append(t); continue }
            let day = calendar.startOfDay(for: due)
            if t.isOverdue(now: now, calendar: calendar) { overdue.append(t) }
            else if day == today { dueToday.append(t) }
            else if day == tomorrow { dueTomorrow.append(t) }
            else if day < weekOut { thisWeek.append(t) }
            else { later.append(t) }
        }
        undated.sort { a, b in a.isFlagged != b.isFlagged ? a.isFlagged : a.createdAt > b.createdAt }
        return [
            DueGroup(title: "Overdue", tasks: overdue),
            DueGroup(title: "Today", tasks: dueToday),
            DueGroup(title: "Tomorrow", tasks: dueTomorrow),
            DueGroup(title: "Next 7 days", tasks: thisWeek),
            DueGroup(title: "Later", tasks: later),
            DueGroup(title: "Anytime", tasks: undated),
        ].filter { !$0.tasks.isEmpty }
    }

    private var completed: [TaskItem] {
        store.data.tasks.filter { $0.isDone && matches($0) }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            .prefix(50).map { $0 }
    }

    private func addQuick() {
        let title = quickTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        store.save(TaskItem(title: title, memberIDs: memberFilter.map { [$0] } ?? []))
        quickTitle = ""
        quickFocused = true
    }
}

struct TaskRow: View {
    @EnvironmentObject var store: FamilyStore
    let task: TaskItem
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            DoneButton(isDone: task.isDone) {
                withAnimation { store.toggleDone(task.id) }
            }
            Button(action: open) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .strikethrough(task.isDone)
                            .foregroundStyle(task.isDone ? Color.secondary : Color.primary)
                        details
                    }
                    Spacer()
                    if task.isFlagged { Image(systemName: "flag.fill").foregroundStyle(.orange).font(.caption) }
                    if let who = store.data.member(task.assigneeID) { MemberAvatar(member: who, size: 24) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var details: some View {
        let forNames = store.data.members(task.memberIDs).map(\.firstName)
        let parts = detailParts(forNames: forNames)
        if !parts.isEmpty {
            HStack(spacing: 4) {
                if task.repeatRule != nil { Image(systemName: "repeat") }
                if task.sourceMessageID != nil { Image(systemName: "envelope") }
                Text(parts.joined(separator: " · "))
            }
            .font(.caption)
            .foregroundStyle(task.isOverdue(now: Date(), calendar: store.calendar) ? Color.red : Color.secondary)
        }
    }

    private func detailParts(forNames: [String]) -> [String] {
        var parts: [String] = []
        if let done = task.completedAt {
            parts.append("Done " + Fmt.shortDay(done))
        } else if let due = task.dueDate {
            parts.append(Fmt.shortDay(due) + (task.hasDueTime ? " " + Fmt.time(due) : ""))
        }
        if !forNames.isEmpty { parts.append("For " + forNames.joined(separator: ", ")) }
        if task.area != .household && task.area != .other { parts.append(task.area.label) }
        return parts
    }
}

struct TaskEditor: View {
    @EnvironmentObject var store: FamilyStore
    @Environment(\.dismiss) var dismiss
    let original: TaskItem
    let onSaved: ((TaskItem) -> Void)?
    @State private var draft: TaskItem

    init(original: TaskItem, onSaved: ((TaskItem) -> Void)? = nil) {
        self.original = original
        self.onSaved = onSaved
        _draft = State(initialValue: original)
    }

    private var isNew: Bool { !store.data.tasks.contains { $0.id == original.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What needs doing?", text: $draft.title, axis: .vertical)
                        .font(.headline)
                    Toggle(isOn: $draft.isFlagged) { Label("Flagged", systemImage: "flag") }
                }
                Section {
                    Toggle("Due date", isOn: hasDue)
                    if let due = draft.dueDate {
                        DatePicker("Due", selection: Binding(get: { due }, set: { draft.dueDate = $0 }),
                                   displayedComponents: draft.hasDueTime ? DatePickerComponents([.date, .hourAndMinute]) : DatePickerComponents.date)
                        Toggle("Include a time", isOn: $draft.hasDueTime)
                        Toggle("Remind me", isOn: $draft.remind)
                        RepeatEditor(rule: $draft.repeatRule, anchor: due)
                    }
                } footer: {
                    if draft.repeatRule != nil {
                        Text("When you check it off, the next one is added automatically.")
                    }
                }
                Section {
                    MemberSinglePicker(title: "Assigned to", members: store.data.members, selection: $draft.assigneeID)
                    Picker("Category", selection: $draft.area) {
                        ForEach(LifeArea.allCases) { a in
                            Label(a.label, systemImage: a.symbol).tag(a)
                        }
                    }
                }
                Section("For") {
                    MemberMultiPicker(members: store.data.members, selection: $draft.memberIDs)
                }
                Section("Notes") {
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...10)
                }
                if let messageID = draft.sourceMessageID, let message = store.data.messages.first(where: { $0.id == messageID }) {
                    Section("From a message") {
                        Label(message.displayTitle, systemImage: message.source.symbol)
                            .foregroundStyle(.secondary)
                    }
                }
                if !isNew {
                    Section {
                        Button(draft.isDone ? "Mark as Not Done" : "Mark as Done") {
                            store.toggleDone(original.id)
                            dismiss()
                        }
                        Button("Delete To-do", role: .destructive) {
                            store.deleteTask(original.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New To-do" : "Edit To-do")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var hasDue: Binding<Bool> {
        Binding(
            get: { draft.dueDate != nil },
            set: { on in
                if on {
                    draft.dueDate = store.calendar.startOfDay(for: Date())
                } else {
                    draft.dueDate = nil
                    draft.hasDueTime = false
                    draft.repeatRule = nil
                    draft.remind = false
                }
            }
        )
    }

    private func save() {
        let wantsReminder = draft.remind && draft.dueDate != nil
        Task { await ReminderScheduler.requestPermissionIfNeeded(wantsReminder) }
        store.save(draft)
        onSaved?(draft)
        dismiss()
    }
}
