import Charts
import SwiftUI

struct TrackersView: View {
    @EnvironmentObject var store: FamilyStore
    @State private var logging: Tracker? = nil
    @State private var editing: Tracker? = nil

    var body: some View {
        List {
            if store.data.trackers.isEmpty {
                ContentUnavailableView("No trackers yet", systemImage: "waveform.path.ecg",
                                       description: Text("Track feeds, diapers, sleep, medicine doses, temperature, growth, reading minutes — anything you count or time."))
            }
            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.trackers) { t in
                        TrackerRow(tracker: t) {
                            if t.kind == .quantity { logging = t } else { withAnimation { store.quickLog(t) } }
                        }
                    }
                }
            }
        }
        .navigationTitle("Trackers")
        .toolbar {
            Button {
                editing = Tracker(name: "", symbol: "star", kind: .event, memberID: store.data.children.first?.id)
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("New tracker")
        }
        .sheet(item: $logging) { t in TrackerLogSheet(tracker: t, original: nil) }
        .sheet(item: $editing) { t in TrackerEditor(original: t) }
    }

    struct TrackerGroup {
        let title: String
        let trackers: [Tracker]
    }

    private var groups: [TrackerGroup] {
        let people: [FamilyMember?] = store.data.members.map { Optional($0) } + [nil]
        return people.compactMap { person -> TrackerGroup? in
            let list = store.data.trackers.filter { $0.memberID == person?.id }
            guard !list.isEmpty else { return nil }
            return TrackerGroup(title: person?.name ?? "Everyone", trackers: list)
        }
    }
}

struct TrackerRow: View {
    @EnvironmentObject var store: FamilyStore
    let tracker: Tracker
    let log: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink {
                TrackerDetailView(trackerID: tracker.id)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: tracker.symbol)
                        .foregroundStyle(tracker.color.color)
                        .frame(width: 30, height: 30)
                        .background(tracker.color.color.opacity(0.15), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tracker.name)
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Button(buttonTitle, action: log)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(running != nil ? Color.red : tracker.color.color)
        }
    }

    private var running: TrackerEntry? { store.data.runningEntry(for: tracker.id) }

    private var buttonTitle: String {
        switch tracker.kind {
        case .event: return "Log"
        case .quantity: return "Log…"
        case .duration: return running == nil ? "Start" : "Stop"
        }
    }

    private var status: String {
        if let running { return "Running since \(Fmt.time(running.date))" }
        guard let last = store.data.lastEntry(for: tracker.id) else { return "Nothing logged yet" }
        var text = Fmt.ago(last.date)
        if let v = last.value { text = "\(Fmt.number(v)) \(tracker.unit) · " + text }
        if let d = last.duration { text = Fmt.duration(d) + " · " + text }
        return text
    }
}

struct TrackerDetailView: View {
    @EnvironmentObject var store: FamilyStore
    @Environment(\.dismiss) var dismiss
    let trackerID: UUID
    @State private var logging = false
    @State private var editingEntry: TrackerEntry? = nil
    @State private var editingTracker: Tracker? = nil

    struct DayTotal: Identifiable {
        let day: Date
        let value: Double
        var id: Date { day }
    }

    var body: some View {
        if let tracker = store.data.tracker(trackerID) {
            content(tracker)
        } else {
            ContentUnavailableView("Tracker deleted", systemImage: "waveform.path.ecg")
        }
    }

    private func content(_ tracker: Tracker) -> some View {
        let entries = store.data.entries(for: tracker.id)
        let running = store.data.runningEntry(for: tracker.id)
        return List {
            Section {
                HStack {
                    Image(systemName: tracker.symbol).font(.title).foregroundStyle(tracker.color.color)
                    VStack(alignment: .leading) {
                        Text(tracker.name).font(.title2.bold())
                        if let m = store.data.member(tracker.memberID) {
                            Text(m.name).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(primaryLabel(tracker, running: running)) {
                        if tracker.kind == .quantity {
                            logging = true
                        } else {
                            withAnimation { store.quickLog(tracker) }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(running != nil ? Color.red : tracker.color.color)
                }
                .padding(.vertical, 4)
            }

            if !entries.isEmpty {
                Section(chartTitle(tracker)) {
                    chart(tracker, entries: entries)
                        .frame(height: 180)
                        .padding(.vertical, 6)
                }
            }

            Section("History") {
                if entries.isEmpty {
                    Text("Nothing logged yet.").foregroundStyle(.secondary)
                }
                ForEach(entries.prefix(200)) { e in
                    Button {
                        editingEntry = e
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entryTitle(e, tracker: tracker))
                                if !e.note.isEmpty { Text(e.note).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(e.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    let list = Array(entries.prefix(200))
                    for i in offsets { store.deleteEntry(list[i].id) }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button {
                    logging = true
                } label: {
                    Label("Add an Earlier Entry", systemImage: "clock.arrow.circlepath")
                }
                Button {
                    editingTracker = tracker
                } label: {
                    Label("Edit Tracker", systemImage: "pencil")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .sheet(isPresented: $logging) { TrackerLogSheet(tracker: tracker, original: nil) }
        .sheet(item: $editingEntry) { e in TrackerLogSheet(tracker: tracker, original: e) }
        .sheet(item: $editingTracker) { t in TrackerEditor(original: t) }
    }

    private func primaryLabel(_ tracker: Tracker, running: TrackerEntry?) -> String {
        switch tracker.kind {
        case .event: return "Log Now"
        case .quantity: return "Log…"
        case .duration: return running == nil ? "Start" : "Stop"
        }
    }

    private func entryTitle(_ e: TrackerEntry, tracker: Tracker) -> String {
        switch tracker.kind {
        case .event: return tracker.name
        case .quantity: return e.value.map { "\(Fmt.number($0)) \(tracker.unit)" } ?? tracker.name
        case .duration:
            if let d = e.duration { return "\(Fmt.duration(d)) · \(Fmt.time(e.date))–\(Fmt.time(e.endDate ?? e.date))" }
            return "Running since \(Fmt.time(e.date))"
        }
    }

    private func chartTitle(_ tracker: Tracker) -> String {
        switch tracker.kind {
        case .event: return "Per day, last 14 days"
        case .quantity: return dailySum(tracker) ? "Total per day, last 14 days" : "Over time"
        case .duration: return "Hours per day, last 14 days"
        }
    }

    /// Bottles and reading minutes add up over a day; weight and temperature don't.
    private func dailySum(_ tracker: Tracker) -> Bool {
        let unit = tracker.unit.lowercased()
        return !["lb", "lbs", "kg", "g", "in", "cm", "°f", "°c", "f", "c", "%"].contains(unit)
            && !tracker.name.lowercased().contains("weight") && !tracker.name.lowercased().contains("height")
            && !tracker.name.lowercased().contains("temp")
    }

    private func dailyTotals(_ tracker: Tracker, entries: [TrackerEntry]) -> [DayTotal] {
        let cal = store.calendar
        let today = cal.startOfDay(for: Date())
        return (0..<14).reversed().compactMap { back -> DayTotal? in
            guard let day = cal.date(byAdding: .day, value: -back, to: today) else { return nil }
            let dayEntries = entries.filter { cal.isDate($0.date, inSameDayAs: day) }
            let value: Double
            switch tracker.kind {
            case .event: value = Double(dayEntries.count)
            case .quantity: value = dayEntries.compactMap(\.value).reduce(0, +)
            case .duration: value = dayEntries.compactMap(\.duration).reduce(0, +) / 3600
            }
            return DayTotal(day: day, value: value)
        }
    }

    @ViewBuilder
    private func chart(_ tracker: Tracker, entries: [TrackerEntry]) -> some View {
        if tracker.kind == .quantity && !dailySum(tracker) {
            let points = entries.filter { $0.value != nil }.prefix(60).reversed().map { $0 }
            Chart(points) { e in
                LineMark(x: .value("Date", e.date), y: .value(tracker.unit, e.value ?? 0))
                    .foregroundStyle(tracker.color.color)
                PointMark(x: .value("Date", e.date), y: .value(tracker.unit, e.value ?? 0))
                    .foregroundStyle(tracker.color.color)
            }
            .chartYScale(domain: .automatic(includesZero: false))
        } else {
            Chart(dailyTotals(tracker, entries: entries)) { d in
                BarMark(x: .value("Day", d.day, unit: .day), y: .value(tracker.unit.isEmpty ? "Count" : tracker.unit, d.value))
                    .foregroundStyle(tracker.color.color.gradient)
                    .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
        }
    }
}

/// Logs a new entry, or edits an existing one.
struct TrackerLogSheet: View {
    @EnvironmentObject var store: FamilyStore
    @Environment(\.dismiss) var dismiss
    let tracker: Tracker
    let original: TrackerEntry?
    @State private var draft: TrackerEntry
    @State private var valueText: String
    @State private var stillRunning: Bool

    init(tracker: Tracker, original: TrackerEntry?) {
        self.tracker = tracker
        self.original = original
        let now = Date()
        var entry = original ?? TrackerEntry(trackerID: tracker.id, date: now)
        if original == nil && tracker.kind == .duration {
            entry.date = now.addingTimeInterval(-30 * 60)
            entry.endDate = now
        }
        _draft = State(initialValue: entry)
        _valueText = State(initialValue: entry.value.map { Fmt.number($0) } ?? "")
        _stillRunning = State(initialValue: original != nil && original?.endDate == nil && tracker.kind == .duration)
    }

    private var parsedValue: Double? {
        Double(valueText.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            Form {
                if tracker.kind == .quantity {
                    Section {
                        HStack {
                            TextField("Amount", text: $valueText)
                                .keyboardType(.decimalPad)
                                .font(.title2.bold())
                            Text(tracker.unit).foregroundStyle(.secondary)
                        }
                        if let last = store.data.lastEntry(for: tracker.id)?.value, original == nil {
                            Button("Same as last time (\(Fmt.number(last)) \(tracker.unit))") {
                                valueText = Fmt.number(last)
                            }
                        }
                    }
                }
                Section {
                    DatePicker(tracker.kind == .duration ? "Started" : "When", selection: $draft.date, in: ...Date())
                    if tracker.kind == .duration {
                        Toggle("Still going", isOn: $stillRunning)
                        if !stillRunning {
                            DatePicker("Ended", selection: Binding(
                                get: { draft.endDate ?? Date() },
                                set: { draft.endDate = $0 }), in: draft.date...)
                        }
                    }
                }
                Section("Note") {
                    TextField(notePrompt, text: $draft.note, axis: .vertical)
                }
                if original != nil {
                    Section {
                        Button("Delete Entry", role: .destructive) {
                            store.deleteEntry(draft.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(tracker.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(tracker.kind == .quantity && parsedValue == nil)
                }
            }
        }
    }

    private var notePrompt: String {
        switch tracker.name.lowercased() {
        case let n where n.contains("diaper"): return "Wet, dirty, both…"
        case let n where n.contains("medic"): return "Dose, which medicine…"
        case let n where n.contains("sleep"), let n where n.contains("nap"): return "Nap, night, how it went…"
        default: return "Optional"
        }
    }

    private func save() {
        var entry = draft
        if tracker.kind == .quantity { entry.value = parsedValue }
        if tracker.kind == .duration {
            entry.endDate = stillRunning ? nil : max(entry.date, entry.endDate ?? Date())
        }
        store.save(entry)
        dismiss()
    }
}

struct TrackerEditor: View {
    @EnvironmentObject var store: FamilyStore
    @Environment(\.dismiss) var dismiss
    let original: Tracker
    @State private var draft: Tracker
    @State private var confirmDelete = false

    init(original: Tracker) {
        self.original = original
        _draft = State(initialValue: original)
    }

    private var isNew: Bool { store.data.tracker(original.id) == nil }

    struct Preset: Identifiable {
        let name: String
        let symbol: String
        let kind: Tracker.Kind
        let unit: String
        let color: PaletteColor
        var id: String { name }
    }

    static let presets: [Preset] = [
        Preset(name: "Bottle", symbol: "drop", kind: .quantity, unit: "oz", color: .pink),
        Preset(name: "Nursing", symbol: "heart", kind: .duration, unit: "", color: .red),
        Preset(name: "Diaper", symbol: "circle.dashed", kind: .event, unit: "", color: .teal),
        Preset(name: "Sleep", symbol: "moon.zzz", kind: .duration, unit: "", color: .indigo),
        Preset(name: "Medicine", symbol: "pills", kind: .event, unit: "", color: .orange),
        Preset(name: "Temperature", symbol: "thermometer.medium", kind: .quantity, unit: "°F", color: .red),
        Preset(name: "Weight", symbol: "scalemass", kind: .quantity, unit: "lb", color: .green),
        Preset(name: "Height", symbol: "ruler", kind: .quantity, unit: "in", color: .mint),
        Preset(name: "Reading", symbol: "book", kind: .quantity, unit: "min", color: .purple),
        Preset(name: "Screen time", symbol: "ipad", kind: .quantity, unit: "min", color: .blue),
        Preset(name: "Tummy time", symbol: "figure.play", kind: .duration, unit: "", color: .yellow),
        Preset(name: "Potty", symbol: "toilet", kind: .event, unit: "", color: .brown),
    ]

    var body: some View {
        NavigationStack {
            Form {
                if isNew {
                    Section("Start from") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Self.presets) { p in
                                    Button {
                                        draft.name = p.name
                                        draft.symbol = p.symbol
                                        draft.kind = p.kind
                                        draft.unit = p.unit
                                        draft.color = p.color
                                    } label: {
                                        VStack(spacing: 4) {
                                            Image(systemName: p.symbol).font(.title3).foregroundStyle(p.color.color)
                                            Text(p.name).font(.caption)
                                        }
                                        .frame(width: 76, height: 58)
                                        .background(draft.name == p.name ? p.color.color.opacity(0.2) : Color(.tertiarySystemFill),
                                                    in: RoundedRectangle(cornerRadius: 10))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                Section {
                    TextField("Name", text: $draft.name)
                    Picker("How it's logged", selection: $draft.kind) {
                        ForEach(Tracker.Kind.allCases) { k in
                            Text(k.label).tag(k)
                        }
                    }
                    if draft.kind == .quantity {
                        TextField("Unit — oz, ml, min, lb, °F", text: $draft.unit)
                            .textInputAutocapitalization(.never)
                    }
                    Picker("For", selection: $draft.memberID) {
                        Text("Everyone").tag(UUID?.none)
                        ForEach(store.data.members) { m in
                            Text(m.name).tag(UUID?.some(m.id))
                        }
                    }
                    Toggle("Show on Today", isOn: $draft.isPinned)
                }
                Section("Colour") {
                    ColorChoice(selection: $draft.color)
                }
                if !isNew {
                    Section {
                        Button("Delete Tracker and Its History", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "New Tracker" : "Edit Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.save(draft)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete \(original.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.deleteTracker(original.id)
                    dismiss()
                }
            } message: {
                Text("Every entry logged for it is deleted too.")
            }
        }
    }
}
