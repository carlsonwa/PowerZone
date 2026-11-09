import PhotosUI
import SwiftUI

/// Messages from school, daycare, coaches and family, each turned into suggested
/// events, to-dos and expenses to accept or dismiss.
struct InboxView: View {
    @EnvironmentObject var store: FamilyStore
    @EnvironmentObject var router: Router
    @State private var capturing = false
    @State private var search = ""

    private var filtered: [InboxMessage] {
        let all = store.data.messages.sorted { $0.receivedAt > $1.receivedAt }
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.body.localizedCaseInsensitiveContains(search) || $0.subject.localizedCaseInsensitiveContains(search)
                || $0.sender.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack(path: $router.inboxPath) {
            List {
                let review = filtered.filter { $0.status == .needsReview }
                let filed = filtered.filter { $0.status == .done }
                if store.data.messages.isEmpty {
                    ContentUnavailableView {
                        Label("No messages yet", systemImage: "tray")
                    } description: {
                        Text("Paste a school email, pick a screenshot of a text from the coach, or scan the flyer from the backpack. Kinboard pulls out the dates, to-dos and costs for you.")
                    } actions: {
                        Button("Capture a Message") { capturing = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
                if !review.isEmpty {
                    Section("To review") {
                        ForEach(review) { m in row(m) }
                    }
                }
                if !filed.isEmpty {
                    Section("Filed") {
                        ForEach(filed) { m in row(m) }
                    }
                }
            }
            .navigationTitle("Inbox")
            .searchable(text: $search, prompt: "Search messages")
            .navigationDestination(for: UUID.self) { id in
                MessageDetailView(messageID: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        capturing = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Capture a message")
                }
            }
            .sheet(isPresented: $capturing) {
                CaptureView { id in router.inboxPath = [id] }
            }
        }
    }

    private func row(_ m: InboxMessage) -> some View {
        NavigationLink(value: m.id) {
            MessageRow(message: m)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.deleteMessage(m.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                store.setStatus(m.status == .done ? .needsReview : .done, for: m.id)
            } label: {
                Label(m.status == .done ? "Review" : "File", systemImage: m.status == .done ? "tray" : "checkmark")
            }
            .tint(.green)
        }
    }
}

struct MessageRow: View {
    @EnvironmentObject var store: FamilyStore
    let message: InboxMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: message.source.symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(message.sender.isEmpty ? message.source.label : message.sender)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(Fmt.shortDay(message.receivedAt)).font(.caption).foregroundStyle(.secondary)
                }
                Text(message.displayTitle).lineLimit(1)
                HStack(spacing: 6) {
                    if !message.pendingSuggestions.isEmpty {
                        Text(message.pendingSuggestions.count == 1 ? "1 suggestion" : "\(message.pendingSuggestions.count) suggestions")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    MemberStack(members: store.data.members(message.memberIDs), size: 16)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Capture

struct CaptureView: View {
    @EnvironmentObject var store: FamilyStore
    @Environment(\.dismiss) var dismiss
    let onSaved: (UUID) -> Void

    @State private var text = ""
    @State private var sender = ""
    @State private var subject = ""
    @State private var source: InboxMessage.Source = .other
    @State private var memberIDs: [UUID] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isReading = false
    @State private var readError: String? = nil
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Paste or type the message…")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                    if isReading {
                        HStack { ProgressView(); Text("Reading the text…").foregroundStyle(.secondary) }
                    }
                    if let readError {
                        Text(readError).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("Message")
                } footer: {
                    Text("Kinboard reads it for dates, to-dos and costs. Nothing is added until you say so.")
                }

                Section("Bring it in") {
                    PasteButton(payloadType: String.self) { strings in
                        let pasted = strings.joined(separator: "\n")
                        DispatchQueue.main.async { append(pasted) }
                    }
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 5, matching: .images) {
                        Label("Screenshot or photo", systemImage: "photo.on.rectangle")
                    }
                    if DocumentScanner.isAvailable {
                        Button {
                            showScanner = true
                        } label: {
                            Label("Scan a paper note", systemImage: "doc.viewfinder")
                        }
                    }
                }

                Section("Details") {
                    TextField("From — e.g. Ms. Alvarez", text: $sender)
                    TextField("Subject (optional)", text: $subject)
                    Picker("Type", selection: $source) {
                        ForEach(InboxMessage.Source.allCases) { s in
                            Label(s.label, systemImage: s.symbol).tag(s)
                        }
                    }
                }

                Section {
                    MemberMultiPicker(members: store.data.members, selection: $memberIDs)
                } header: {
                    Text("About")
                } footer: {
                    Text("Left blank, Kinboard tags anyone named in the message.")
                }
            }
            .navigationTitle("Capture Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isReading)
                }
            }
            .onChange(of: photoItems) {
                guard !photoItems.isEmpty else { return }
                let items = photoItems
                photoItems = []
                Task { await readPhotos(items) }
            }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScanner(onScan: { images in
                    showScanner = false
                    Task { await read(images) }
                }, onCancel: {
                    showScanner = false
                })
                .ignoresSafeArea()
            }
        }
    }

    private func append(_ newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        text = text.isEmpty ? trimmed : text + "\n\n" + trimmed
    }

    @MainActor
    private func readPhotos(_ items: [PhotosPickerItem]) async {
        isReading = true
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(image)
            }
        }
        await read(images)
    }

    @MainActor
    private func read(_ images: [UIImage]) async {
        isReading = true
        readError = nil
        defer { isReading = false }
        do {
            let found = try await TextRecognizer.text(in: images)
            if found.isEmpty {
                readError = "No text found in that picture."
            } else {
                append(found)
            }
        } catch {
            readError = "Couldn't read the picture: \(error.localizedDescription)"
        }
    }

    private func save() {
        let extractor = store.extractor()
        var people = memberIDs
        if people.isEmpty { people = extractor.mentionedMembers(in: text) }
        var kind = source
        if kind == .other { kind = MessageExtractor.guessSource(subject + "\n" + text) }
        let message = InboxMessage(sender: sender.trimmingCharacters(in: .whitespaces),
                                   subject: subject.trimmingCharacters(in: .whitespaces),
                                   body: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                   source: kind, memberIDs: people)
        store.save(message, rescan: true)
        dismiss()
        onSaved(message.id)
    }
}

// MARK: - Review

struct MessageDetailView: View {
    @EnvironmentObject var store: FamilyStore
    @Environment(\.dismiss) var dismiss
    let messageID: UUID
    @State private var editingSuggestion: SuggestionDraft? = nil
    @State private var editingMessage: InboxMessage? = nil
    @State private var confirmDelete = false

    enum SuggestionDraft: Identifiable {
        case event(FamilyEvent, UUID)
        case task(TaskItem, UUID)
        case expense(Expense, UUID)

        var id: UUID {
            switch self {
            case .event(_, let s), .task(_, let s), .expense(_, let s): return s
            }
        }
    }

    private var message: InboxMessage? { store.data.messages.first { $0.id == messageID } }

    var body: some View {
        Group {
            if let message {
                content(message)
            } else {
                ContentUnavailableView("Message deleted", systemImage: "tray")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ message: InboxMessage) -> some View {
        let pending = message.pendingSuggestions
        let dismissed = message.suggestions.filter { $0.state == .dismissed }
        let made = store.data.items(fromMessage: message.id)
        let madeCount = made.events.count + made.tasks.count + made.expenses.count
        return List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label(message.source.label, systemImage: message.source.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(message.displayTitle).font(.title3.bold())
                    HStack {
                        if !message.sender.isEmpty { Text(message.sender) }
                        Text(message.receivedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    let people = store.data.members(message.memberIDs)
                    if !people.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(people) { m in
                                HStack(spacing: 4) {
                                    MemberAvatar(member: m, size: 18)
                                    Text(m.firstName).font(.caption)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if !pending.isEmpty {
                Section {
                    ForEach(pending) { s in
                        SuggestionRow(suggestion: s,
                                      onAdd: { withAnimation { store.acceptSuggestion(s.id, in: message.id) } },
                                      onEdit: { editingSuggestion = draft(for: s, message: message) },
                                      onDismiss: { withAnimation { store.markSuggestion(s.id, in: message.id, as: .dismissed) } })
                    }
                    if pending.count > 1 {
                        Button {
                            withAnimation {
                                for s in pending { store.acceptSuggestion(s.id, in: message.id) }
                            }
                        } label: {
                            Label("Add all \(pending.count)", systemImage: "plus.circle")
                        }
                    }
                } header: {
                    Text("Found in this message")
                } footer: {
                    Text("Add puts it straight on the calendar or list. Tap a suggestion to check the details first.")
                }
            } else if message.suggestions.isEmpty {
                Section {
                    Text("No dates, to-dos or costs found. You can still add something from it by hand.")
                        .foregroundStyle(.secondary)
                }
            }

            if madeCount > 0 {
                Section("Added from this message") {
                    ForEach(made.events) { e in
                        NavigationLink {
                            EventDetailView(eventID: e.id, occurrenceStart: e.start)
                        } label: {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(e.title)
                                    Text(e.start.formatted(date: .abbreviated, time: e.isAllDay ? Date.FormatStyle.TimeStyle.omitted : Date.FormatStyle.TimeStyle.shortened))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "calendar")
                            }
                        }
                    }
                    ForEach(made.tasks) { t in
                        TaskRow(task: t) { editingSuggestion = .task(t, UUID()) }
                    }
                    ForEach(made.expenses) { e in
                        Button {
                            editingSuggestion = .expense(e, UUID())
                        } label: {
                            HStack {
                                Label(e.title, systemImage: "dollarsign.circle")
                                Spacer()
                                Text(Fmt.money(e.amountCents)).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !dismissed.isEmpty {
                Section("Dismissed") {
                    ForEach(dismissed) { s in
                        HStack {
                            Image(systemName: s.kind.symbol).foregroundStyle(.secondary)
                            Text(s.title).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            Button("Restore") {
                                withAnimation { store.markSuggestion(s.id, in: message.id, as: .pending) }
                                store.setStatus(.needsReview, for: message.id)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Section("Message") {
                Text(message.body)
                    .textSelection(.enabled)
                    .font(.callout)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        store.setStatus(message.status == .done ? .needsReview : .done, for: message.id)
                    } label: {
                        Label(message.status == .done ? "Move to To Review" : "File as Done",
                              systemImage: message.status == .done ? "tray" : "checkmark.circle")
                    }
                    Button {
                        editingMessage = message
                    } label: {
                        Label("Edit Message", systemImage: "pencil")
                    }
                    Button {
                        store.save(message, rescan: true)
                    } label: {
                        Label("Look for Suggestions Again", systemImage: "sparkle.magnifyingglass")
                    }
                    Divider()
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete Message", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $editingSuggestion) { draft in
            suggestionEditor(draft, messageID: message.id)
        }
        .sheet(item: $editingMessage) { m in
            MessageEditor(original: m)
        }
        .confirmationDialog("Delete this message?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Message", role: .destructive) {
                store.deleteMessage(message.id)
                dismiss()
            }
        } message: {
            Text("Events, to-dos and expenses already added from it are kept.")
        }
    }

    private func draft(for s: Suggestion, message: InboxMessage) -> SuggestionDraft {
        switch s.kind {
        case .event: return .event(s.makeEvent(messageID: message.id, calendar: store.calendar), s.id)
        case .task: return .task(s.makeTask(messageID: message.id), s.id)
        case .expense: return .expense(s.makeExpense(messageID: message.id, calendar: store.calendar), s.id)
        }
    }

    @ViewBuilder
    private func suggestionEditor(_ draft: SuggestionDraft, messageID: UUID) -> some View {
        switch draft {
        case .event(let event, let suggestionID):
            EventEditor(original: event) { _ in store.markSuggestion(suggestionID, in: messageID, as: .added) }
        case .task(let task, let suggestionID):
            TaskEditor(original: task) { _ in store.markSuggestion(suggestionID, in: messageID, as: .added) }
        case .expense(let expense, let suggestionID):
            ExpenseEditor(original: expense) { _ in store.markSuggestion(suggestionID, in: messageID, as: .added) }
        }
    }
}

struct SuggestionRow: View {
    @Environment(\.calendar) var calendar
    let suggestion: Suggestion
    let onAdd: () -> Void
    let onEdit: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: suggestion.kind.symbol)
                .foregroundStyle(tint)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.title).font(.body.weight(.medium))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(isPast ? Color.orange : Color.secondary)
                if !suggestion.excerpt.isEmpty {
                    Text("“\(suggestion.excerpt)”")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onEdit)
            VStack(spacing: 8) {
                Button("Add", action: onAdd)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.vertical, 2)
    }

    private var tint: Color {
        switch suggestion.kind {
        case .event: return .blue
        case .task: return .orange
        case .expense: return .green
        }
    }

    private var isPast: Bool {
        guard let date = suggestion.date, suggestion.kind != .expense else { return false }
        return date < calendar.startOfDay(for: Date())
    }

    private var detail: String {
        var parts: [String] = [suggestion.kind.label]
        if let date = suggestion.date, suggestion.kind != .expense {
            let day = Fmt.dayTitle(date, calendar: calendar)
            if suggestion.isAllDay {
                parts.append(suggestion.kind == .task ? "due \(day)" : day)
            } else {
                parts.append((suggestion.kind == .task ? "due " : "") + "\(day), \(Fmt.time(date))")
            }
        }
        if let cents = suggestion.amountCents { parts.append(Fmt.money(cents)) }
        if isPast { parts.append("in the past") }
        return parts.joined(separator: " · ")
    }
}

struct MessageEditor: View {
    @EnvironmentObject var store: FamilyStore
    @Environment(\.dismiss) var dismiss
    let original: InboxMessage
    @State private var draft: InboxMessage

    init(original: InboxMessage) {
        self.original = original
        _draft = State(initialValue: original)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("From") {
                    TextField("Sender", text: $draft.sender)
                    TextField("Subject", text: $draft.subject)
                    Picker("Type", selection: $draft.source) {
                        ForEach(InboxMessage.Source.allCases) { s in
                            Label(s.label, systemImage: s.symbol).tag(s)
                        }
                    }
                }
                Section("About") {
                    MemberMultiPicker(members: store.data.members, selection: $draft.memberIDs)
                }
                Section {
                    TextEditor(text: $draft.body).frame(minHeight: 200)
                } header: {
                    Text("Message")
                } footer: {
                    Text("Changing the text looks for suggestions again. Ones you've already added or dismissed stay as they are.")
                }
            }
            .navigationTitle("Edit Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.save(draft, rescan: draft.body != original.body)
                        dismiss()
                    }
                    .disabled(draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
