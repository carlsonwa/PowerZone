import SwiftUI

/// Month grid on top, the chosen day's events and to-dos underneath.
struct CalendarScreen: View {
    @EnvironmentObject var store: FamilyStore
    @State private var month = Date()
    @State private var selected = Date()
    @State private var memberFilter: UUID? = nil
    @State private var newEvent: FamilyEvent? = nil

    private var calendar: Calendar { store.calendar }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MonthGrid(month: month, selected: $selected, busy: busyDays)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
                Section {
                    let occurrences = store.data.occurrences(on: selected, calendar: calendar, memberID: memberFilter)
                    let tasks = store.data.tasksDue(on: selected, calendar: calendar)
                        .filter { memberFilter == nil || $0.assigneeID == memberFilter || $0.memberIDs.contains(memberFilter!) }
                    if occurrences.isEmpty && tasks.isEmpty {
                        Text("Nothing planned.").foregroundStyle(.secondary)
                    }
                    ForEach(occurrences) { occ in
                        NavigationLink {
                            EventDetailView(eventID: occ.event.id, occurrenceStart: occ.start)
                        } label: {
                            EventRow(occurrence: occ, members: store.data.members(occ.event.memberIDs))
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                store.deleteOccurrence(occ)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    ForEach(tasks) { t in
                        HStack(spacing: 10) {
                            DoneButton(isDone: t.isDone) { withAnimation { store.toggleDone(t.id) } }
                            Text(t.title)
                            Spacer()
                            Text("To-do").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(Fmt.dayTitle(selected, calendar: calendar))
                }
            }
            .navigationTitle(month.formatted(.dateTime.month(.wide).year()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Previous month")
                    Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Next month")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Today") {
                        month = Date()
                        selected = Date()
                    }
                    filterMenu
                    Button {
                        newEvent = FamilyEvent.newDraft(on: selected, calendar: calendar)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New event")
                }
            }
            .sheet(item: $newEvent) { draft in
                EventEditor(original: draft)
            }
        }
    }

    private var busyDays: [String: [PaletteColor]] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [:] }
        let start = calendar.date(byAdding: .day, value: -7, to: interval.start) ?? interval.start
        let end = calendar.date(byAdding: .day, value: 14, to: interval.end) ?? interval.end
        if let memberFilter {
            var filtered = store.data
            filtered.events = filtered.events.filter { $0.memberIDs.contains(memberFilter) }
            return filtered.busyDays(from: start, to: end, calendar: calendar)
        }
        return store.data.busyDays(from: start, to: end, calendar: calendar)
    }

    private var filterMenu: some View {
        Menu {
            Picker("Show", selection: $memberFilter) {
                Text("Everyone").tag(UUID?.none)
                ForEach(store.data.members) { m in
                    Text(m.name).tag(UUID?.some(m.id))
                }
            }
        } label: {
            Image(systemName: memberFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel("Filter by person")
    }

    private func shiftMonth(_ delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: month) else { return }
        month = next
        if let first = calendar.dateInterval(of: .month, for: next)?.start {
            selected = calendar.isDate(next, equalTo: Date(), toGranularity: .month) ? Date() : first
        }
    }
}

struct MonthGrid: View {
    let month: Date
    @Binding var selected: Date
    let busy: [String: [PaletteColor]]
    @Environment(\.calendar) var calendar

    var body: some View {
        let days = gridDays
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(weekdayHeaders, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(days.indices, id: \.self) { i in
                    if let day = days[i] {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
    }

    private var weekdayHeaders: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }

    /// The month's days, with blanks before the 1st so it lands under its weekday.
    private var gridDays: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        var result: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<count {
            result.append(calendar.date(byAdding: .day, value: offset, to: interval.start))
        }
        return result
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        let isToday = calendar.isDateInToday(day)
        let colors = busy[DayKey.make(day, calendar: calendar)] ?? []
        return Button {
            selected = day
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.callout.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.white : (isToday ? Color.accentColor : Color.primary))
                    .frame(width: 32, height: 32)
                    .background(isSelected ? Color.accentColor : Color.clear, in: Circle())
                HStack(spacing: 2) {
                    ForEach(colors.prefix(3), id: \.self) { c in
                        Circle().fill(c.color).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (colors.isEmpty ? "" : ", has events"))
    }
}

// MARK: - Event detail

struct EventDetailView: View {
    @EnvironmentObject var store: FamilyStore
    @Environment(\.dismiss) var dismiss
    let eventID: UUID
    let occurrenceStart: Date
    @State private var editing: FamilyEvent? = nil
    @State private var showAppleCalendar = false
    @State private var confirmDelete = false

    private var event: FamilyEvent? { store.data.events.first { $0.id == eventID } }

    var body: some View {
        Group {
            if let event {
                content(event)
            } else {
                ContentUnavailableView("Event deleted", systemImage: "calendar.badge.minus")
            }
        }
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ event: FamilyEvent) -> some View {
        let occurrence = event.occurrence(startingAt: occurrenceStart, calendar: store.calendar)
        let people = store.data.members(event.memberIDs)
        return List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title).font(.title2.bold())
                    Text(occurrence.start.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                    Text(timeText(occurrence)).foregroundStyle(.secondary)
                    if let rule = event.repeatRule {
                        Label(rule.summary(calendar: store.calendar), systemImage: "repeat")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            if !people.isEmpty {
                Section("Who") {
                    ForEach(people) { m in
                        HStack { MemberAvatar(member: m, size: 26); Text(m.name) }
                    }
                }
            }
            Section {
                LabeledContent("Category") { Label(event.area.label, systemImage: event.area.symbol) }
                if !event.location.isEmpty {
                    if let url = mapsURL(event.location) {
                        Link(destination: url) {
                            LabeledContent("Where", value: event.location)
                        }
                    } else {
                        LabeledContent("Where", value: event.location)
                    }
                }
                LabeledContent("Reminder", value: event.reminder.label)
            }
            if !event.notes.isEmpty {
                Section("Notes") { Text(event.notes).textSelection(.enabled) }
            }
            if let messageID = event.sourceMessageID, let message = store.data.messages.first(where: { $0.id == messageID }) {
                Section("From a message") {
                    NavigationLink {
                        MessageDetailView(messageID: message.id)
                    } label: {
                        Label(message.displayTitle, systemImage: message.source.symbol)
                    }
                }
            }
            Section {
                Button {
                    showAppleCalendar = true
                } label: {
                    Label("Add to Apple Calendar…", systemImage: "calendar.badge.plus")
                }
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete Event", systemImage: "trash")
                }
            } footer: {
                Text("Adding to Apple Calendar lets you put it on a shared iCloud calendar so everyone in the family sees it.")
            }
        }
        .toolbar {
            Button("Edit") { editing = event }
        }
        .sheet(item: $editing) { draft in
            EventEditor(original: draft)
        }
        .sheet(isPresented: $showAppleCalendar) {
            AppleCalendarEditor(event: event, occurrence: occurrence) { showAppleCalendar = false }
                .ignoresSafeArea()
        }
        .confirmationDialog("Delete this event?", isPresented: $confirmDelete, titleVisibility: .visible) {
            if event.repeatRule != nil {
                Button("Delete This Event Only", role: .destructive) {
                    store.deleteOccurrence(occurrence)
                    dismiss()
                }
                Button("Delete All Future and Past Events", role: .destructive) {
                    store.deleteEvent(event.id)
                    dismiss()
                }
            } else {
                Button("Delete Event", role: .destructive) {
                    store.deleteEvent(event.id)
                    dismiss()
                }
            }
        }
    }

    private func timeText(_ occurrence: EventOccurrence) -> String {
        let cal = store.calendar
        if occurrence.event.isAllDay {
            let lastDay = occurrence.end.addingTimeInterval(-1)
            if cal.isDate(occurrence.start, inSameDayAs: lastDay) { return "All day" }
            return "All day, until " + lastDay.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return Fmt.eventTime(occurrence)
    }

    private func mapsURL(_ place: String) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: place)]
        return components?.url
    }
}

// MARK: - Event editor

struct EventEditor: View {
    @EnvironmentObject var store: FamilyStore
    @Environment(\.dismiss) var dismiss
    let original: FamilyEvent
    let onSaved: ((FamilyEvent) -> Void)?
    @State private var draft: FamilyEvent

    init(original: FamilyEvent, onSaved: ((FamilyEvent) -> Void)? = nil) {
        self.original = original
        self.onSaved = onSaved
        _draft = State(initialValue: original)
    }

    private var isNew: Bool { !store.data.events.contains { $0.id == original.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $draft.title)
                        .font(.headline)
                    TextField("Location", text: $draft.location)
                }
                Section {
                    Toggle("All-day", isOn: allDayBinding)
                    if draft.isAllDay {
                        DatePicker("Starts", selection: startBinding, displayedComponents: .date)
                        DatePicker("Ends", selection: $draft.end, in: draft.start..., displayedComponents: .date)
                    } else {
                        DatePicker("Starts", selection: startBinding)
                        DatePicker("Ends", selection: $draft.end, in: draft.start...)
                    }
                }
                Section {
                    RepeatEditor(rule: $draft.repeatRule, anchor: draft.start)
                }
                Section("Who") {
                    MemberMultiPicker(members: store.data.members, selection: $draft.memberIDs)
                }
                Section {
                    Picker("Category", selection: $draft.area) {
                        ForEach(LifeArea.allCases) { a in
                            Label(a.label, systemImage: a.symbol).tag(a)
                        }
                    }
                    Picker("Reminder", selection: $draft.reminder) {
                        ForEach(ReminderOffset.allCases) { r in
                            Text(r.label).tag(r)
                        }
                    }
                } footer: {
                    if draft.reminder != .none {
                        Text(draft.isAllDay ? "All-day reminders arrive at 9 AM." : "Reminders need notifications turned on for Kinboard.")
                    }
                }
                Section("Notes") {
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...10)
                }
            }
            .navigationTitle(isNew ? "New Event" : "Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    /// Moving the start keeps the length of the event.
    private var startBinding: Binding<Date> {
        Binding(
            get: { draft.start },
            set: { newStart in
                let length = draft.end.timeIntervalSince(draft.start)
                draft.start = newStart
                draft.end = newStart.addingTimeInterval(max(0, length))
            }
        )
    }

    private var allDayBinding: Binding<Bool> {
        Binding(
            get: { draft.isAllDay },
            set: { on in
                let cal = store.calendar
                draft.isAllDay = on
                if on {
                    draft.start = cal.startOfDay(for: draft.start)
                    draft.end = max(draft.start, cal.startOfDay(for: draft.end))
                } else {
                    let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: draft.start) ?? draft.start
                    draft.start = start
                    draft.end = start.addingTimeInterval(3600)
                }
            }
        )
    }

    private func save() {
        let wantsReminder = draft.reminder != .none
        Task { await ReminderScheduler.requestPermissionIfNeeded(wantsReminder) }
        store.save(draft)
        onSaved?(draft)
        dismiss()
    }
}
