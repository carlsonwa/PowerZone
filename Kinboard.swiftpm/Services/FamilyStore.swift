import SwiftUI

/// Owns the family's data, saves it to one JSON file on the device, and keeps reminders
/// scheduled. Views read `store.data` and change it through the methods here.
@MainActor
final class FamilyStore: ObservableObject {
    @Published var data: FamilyData {
        didSet { scheduleSave() }
    }
    /// Set when the saved file existed but couldn't be read. The unreadable file is kept
    /// beside the new one rather than overwritten.
    @Published var loadProblem: String? = nil

    var calendar: Calendar { Calendar.current }
    let detector = AppleDateDetector()

    private let folder: URL
    private var fileURL: URL { folder.appendingPathComponent("family.json") }
    private var receiptsFolder: URL { folder.appendingPathComponent("Receipts", isDirectory: true) }
    private var saveTask: Task<Void, Never>?
    private var backedUpThisLaunch = false

    init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Kinboard", isDirectory: true)
        try? fm.createDirectory(at: dir.appendingPathComponent("Receipts", isDirectory: true),
                                withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("family.json")

        var loaded = FamilyData()
        var problem: String?
        if let raw = try? Data(contentsOf: url) {
            do {
                loaded = try FamilyData.decoder().decode(FamilyData.self, from: raw)
            } catch {
                let keep = dir.appendingPathComponent("family-unreadable-\(Int(Date().timeIntervalSince1970)).json")
                try? fm.moveItem(at: url, to: keep)
                problem = "Kinboard couldn't read its saved data, so it started fresh. The old file was kept as \(keep.lastPathComponent) in case it can be recovered. (\(error.localizedDescription))"
            }
        }
        folder = dir
        data = loaded
        loadProblem = problem
    }

    // MARK: - Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        do {
            // Keep the previous version once per launch, as a cheap undo for a bad day.
            if !backedUpThisLaunch, FileManager.default.fileExists(atPath: fileURL.path) {
                let backup = folder.appendingPathComponent("family-previous.json")
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.copyItem(at: fileURL, to: backup)
                backedUpThisLaunch = true
            }
            let encoded = try FamilyData.encoder().encode(data)
            try encoded.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch {
            print("Kinboard save failed: \(error)")
        }
        let snapshot = data
        Task { await ReminderScheduler.reschedule(snapshot) }
    }

    func backupData() throws -> Data {
        try FamilyData.encoder().encode(data)
    }

    func replaceAll(with newData: FamilyData) {
        data = newData
        saveNow()
    }

    func loadSample() {
        replaceAll(with: SampleData.make(now: Date(), calendar: calendar, detector: detector))
    }

    func eraseEverything() {
        if let files = try? FileManager.default.contentsOfDirectory(at: receiptsFolder, includingPropertiesForKeys: nil) {
            for file in files { try? FileManager.default.removeItem(at: file) }
        }
        replaceAll(with: FamilyData())
    }

    // MARK: - Generic upsert

    private func upsert<T: Identifiable>(_ item: T, _ keyPath: WritableKeyPath<FamilyData, [T]>) where T.ID == UUID {
        if let i = data[keyPath: keyPath].firstIndex(where: { $0.id == item.id }) {
            data[keyPath: keyPath][i] = item
        } else {
            data[keyPath: keyPath].append(item)
        }
    }

    // MARK: - People

    func save(_ member: FamilyMember) { upsert(member, \.members) }
    func deleteMember(_ id: UUID) { data.deleteMember(id: id) }
    func save(_ contact: Contact) { upsert(contact, \.contacts) }
    func deleteContact(_ id: UUID) { data.contacts.removeAll { $0.id == id } }
    func save(_ item: InfoItem) { upsert(item, \.info) }
    func deleteInfo(_ id: UUID) { data.info.removeAll { $0.id == id } }

    // MARK: - Calendar

    func save(_ event: FamilyEvent) {
        var e = event
        e.title = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if e.isAllDay {
            e.start = calendar.startOfDay(for: e.start)
            e.end = max(e.start, calendar.startOfDay(for: e.end))
        } else {
            e.start = Self.wholeMinute(e.start)
            e.end = max(e.start, Self.wholeMinute(e.end))
        }
        upsert(e, \.events)
    }

    func deleteEvent(_ id: UUID) { data.events.removeAll { $0.id == id } }

    func deleteOccurrence(_ occurrence: EventOccurrence) {
        data.deleteOccurrence(occurrence, calendar: calendar)
    }

    // MARK: - Tasks

    func save(_ task: TaskItem) {
        var t = task
        t.title = t.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let due = t.dueDate {
            t.dueDate = t.hasDueTime ? Self.wholeMinute(due) : calendar.startOfDay(for: due)
        } else {
            t.hasDueTime = false
            t.repeatRule = nil
            t.remind = false
        }
        upsert(t, \.tasks)
    }

    func deleteTask(_ id: UUID) { data.tasks.removeAll { $0.id == id } }

    func toggleDone(_ id: UUID) {
        guard let task = data.tasks.first(where: { $0.id == id }) else { return }
        if task.isDone {
            data.reopenTask(id: id)
        } else {
            data.completeTask(id: id, at: Date(), calendar: calendar)
        }
    }

    func toggleFlag(_ id: UUID) {
        guard let i = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        data.tasks[i].isFlagged.toggle()
    }

    // MARK: - Spending

    func save(_ expense: Expense) { upsert(expense, \.expenses) }

    func deleteExpense(_ id: UUID) {
        if let file = data.expenses.first(where: { $0.id == id })?.receiptFile { deleteReceipt(file) }
        data.expenses.removeAll { $0.id == id }
    }

    func setBudget(_ cents: Int?, for category: Expense.Category) {
        if let cents, cents > 0 {
            data.budgets[category.rawValue] = cents
        } else {
            data.budgets.removeValue(forKey: category.rawValue)
        }
    }

    func storeReceipt(_ imageData: Data) -> String? {
        let name = UUID().uuidString + ".jpg"
        do {
            try imageData.write(to: receiptsFolder.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    func receiptURL(_ name: String) -> URL { receiptsFolder.appendingPathComponent(name) }

    func deleteReceipt(_ name: String) {
        try? FileManager.default.removeItem(at: receiptURL(name))
    }

    // MARK: - Trackers

    func save(_ tracker: Tracker) { upsert(tracker, \.trackers) }
    func deleteTracker(_ id: UUID) { data.deleteTracker(id: id) }
    func save(_ entry: TrackerEntry) { upsert(entry, \.trackerEntries) }
    func deleteEntry(_ id: UUID) { data.trackerEntries.removeAll { $0.id == id } }

    /// One-tap logging: an event tracker records "now", a duration tracker starts or stops.
    /// Quantity trackers need a number, so the caller shows a sheet instead.
    func quickLog(_ tracker: Tracker) {
        switch tracker.kind {
        case .event:
            save(TrackerEntry(trackerID: tracker.id, date: Date()))
        case .duration:
            if let running = data.runningEntry(for: tracker.id) {
                var stopped = running
                stopped.endDate = Date()
                save(stopped)
            } else {
                save(TrackerEntry(trackerID: tracker.id, date: Date()))
            }
        case .quantity:
            break
        }
    }

    // MARK: - Inbox

    func extractor() -> MessageExtractor {
        MessageExtractor(detector: detector, calendar: calendar, now: Date(), members: data.members)
    }

    /// Saves a captured message, reading it for suggestions the first time (or again when
    /// `rescan` is set — keeping anything already added or dismissed).
    func save(_ message: InboxMessage, rescan: Bool) {
        var m = message
        if rescan {
            let fresh = extractor().suggestions(for: m.body, defaultMemberIDs: m.memberIDs)
            let handled = m.suggestions.filter { $0.state != .pending }
            m.suggestions = handled + fresh.filter { new in
                !handled.contains { $0.kind == new.kind && $0.title == new.title }
            }
            if !m.pendingSuggestions.isEmpty { m.status = .needsReview }
        }
        upsert(m, \.messages)
    }

    func deleteMessage(_ id: UUID) { data.messages.removeAll { $0.id == id } }

    func setStatus(_ status: InboxMessage.Status, for id: UUID) {
        guard let i = data.messages.firstIndex(where: { $0.id == id }) else { return }
        data.messages[i].status = status
    }

    func acceptSuggestion(_ suggestionID: UUID, in messageID: UUID) {
        data.accept(suggestionID: suggestionID, inMessage: messageID, calendar: calendar)
    }

    func markSuggestion(_ suggestionID: UUID, in messageID: UUID, as state: Suggestion.State) {
        data.markSuggestion(suggestionID, inMessage: messageID, as: state)
    }

    // MARK: - Helpers

    static func wholeMinute(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }
}
