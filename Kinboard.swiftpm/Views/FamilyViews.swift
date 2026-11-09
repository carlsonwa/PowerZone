import SwiftUI

/// People, trackers, contacts, the facts worth keeping, and settings.
struct FamilyView: View {
    @EnvironmentObject var store: FamilyStore
    @State private var editingMember: FamilyMember? = nil

    var body: some View {
        List {
            Section("People") {
                ForEach(store.data.members) { m in
                    NavigationLink {
                        MemberDetailView(memberID: m.id)
                    } label: {
                        HStack(spacing: 12) {
                            MemberAvatar(member: m, size: 36)
                            VStack(alignment: .leading) {
                                Text(m.name)
                                Text(subtitle(m)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Button {
                    editingMember = FamilyMember(name: "", role: .child,
                                                 color: PaletteColor.allCases[store.data.members.count % PaletteColor.allCases.count])
                } label: {
                    Label("Add a Person", systemImage: "person.badge.plus")
                }
            }
            Section {
                NavigationLink {
                    TrackersView()
                } label: {
                    Label("Trackers", systemImage: "waveform.path.ecg")
                        .badge(store.data.trackers.count)
                }
                NavigationLink {
                    ContactsView()
                } label: {
                    Label("Contacts", systemImage: "person.crop.rectangle.stack")
                        .badge(store.data.contacts.count)
                }
                NavigationLink {
                    InfoListView(memberID: nil)
                } label: {
                    Label("Important Info", systemImage: "list.clipboard")
                        .badge(store.data.info.count)
                }
            } footer: {
                Text("Trackers log feeds, sleep, medicine and growth. Important Info keeps sizes, allergies, insurance numbers and school details at hand.")
            }
            Section {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .navigationTitle("Family")
        .sheet(item: $editingMember) { m in
            MemberEditor(member: m)
        }
    }

    private func subtitle(_ m: FamilyMember) -> String {
        if let birthday = m.birthday { return "\(m.role.label) · \(Fmt.age(birthday: birthday))" }
        return m.role.label
    }
}

// MARK: - Member

struct MemberDetailView: View {
    @EnvironmentObject var store: FamilyStore
    let memberID: UUID
    @State private var editing: FamilyMember? = nil
    @State private var logging: Tracker? = nil
    @State private var newTracker: Tracker? = nil
    @State private var newInfo: InfoItem? = nil

    private var member: FamilyMember? { store.data.member(memberID) }

    var body: some View {
        Group {
            if let member {
                content(member)
            } else {
                ContentUnavailableView("Removed", systemImage: "person.slash")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ member: FamilyMember) -> some View {
        let calendar = store.calendar
        let now = Date()
        let soon = calendar.date(byAdding: .day, value: 14, to: now) ?? now
        let upcoming = store.data.occurrences(from: calendar.startOfDay(for: now), to: soon,
                                              calendar: calendar, memberID: member.id)
        let tasks = store.data.openTasks().filter { $0.assigneeID == member.id || $0.memberIDs.contains(member.id) }
        let trackers = store.data.trackers.filter { $0.memberID == member.id }
        let info = store.data.info.filter { $0.memberID == member.id }
        let contacts = store.data.contacts.filter { $0.memberIDs.contains(member.id) }
        let monthSpend = store.data.totalCents(store.data.expenses(inMonthOf: now, calendar: calendar)
            .filter { $0.memberIDs.contains(member.id) })

        return List {
            Section {
                HStack(spacing: 16) {
                    MemberAvatar(member: member, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(member.name).font(.title2.bold())
                        if let birthday = member.birthday {
                            Text("\(Fmt.age(birthday: birthday)) · born \(birthday.formatted(date: .abbreviated, time: .omitted))")
                                .font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            Text(member.role.label).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if member.role == .child || !trackers.isEmpty {
                Section("Trackers") {
                    ForEach(trackers) { t in
                        TrackerRow(tracker: t) {
                            if t.kind == .quantity { logging = t } else { withAnimation { store.quickLog(t) } }
                        }
                    }
                    Button {
                        newTracker = Tracker(name: "", symbol: "star", kind: .event, memberID: member.id, color: member.color)
                    } label: {
                        Label("Add a Tracker", systemImage: "plus")
                    }
                }
            }

            Section("Next two weeks") {
                if upcoming.isEmpty { Text("Nothing scheduled.").foregroundStyle(.secondary) }
                ForEach(upcoming.prefix(8)) { occ in
                    NavigationLink {
                        EventDetailView(eventID: occ.event.id, occurrenceStart: occ.start)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(occ.event.title)
                            Text("\(Fmt.shortDay(occ.start)) · \(Fmt.eventTime(occ))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !tasks.isEmpty {
                Section("To-dos") {
                    ForEach(tasks.prefix(8)) { t in
                        TaskRow(task: t) {}
                    }
                }
            }

            Section {
                ForEach(info) { item in
                    InfoRow(item: item)
                }
                .onDelete { offsets in
                    for i in offsets { store.deleteInfo(info[i].id) }
                }
                Button {
                    newInfo = InfoItem(memberID: member.id, category: .medical, title: "", value: "")
                } label: {
                    Label("Add Info", systemImage: "plus")
                }
            } header: {
                Text("Important info")
            } footer: {
                Text("Allergies, sizes, school, doctor — anything you get asked for.")
            }

            if !contacts.isEmpty {
                Section("Contacts") {
                    ForEach(contacts) { c in
                        NavigationLink {
                            ContactDetailView(contactID: c.id)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(c.name)
                                if !c.role.isEmpty { Text(c.role).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }

            if monthSpend > 0 {
                Section {
                    LabeledContent("Spent on \(member.firstName) this month", value: Fmt.money(monthSpend))
                }
            }
        }
        .toolbar {
            Button("Edit") { editing = member }
        }
        .sheet(item: $editing) { m in MemberEditor(member: m) }
        .sheet(item: $logging) { t in TrackerLogSheet(tracker: t, original: nil) }
        .sheet(item: $newTracker) { t in TrackerEditor(original: t) }
        .sheet(item: $newInfo) { item in InfoEditor(original: item) }
    }
}

struct MemberEditor: View {
    @EnvironmentObject var store: FamilyStore
    @Environment(\.dismiss) var dismiss
    let member: FamilyMember
    @State private var draft: FamilyMember
    @State private var hasBirthday: Bool
    @State private var confirmDelete = false

    init(member: FamilyMember) {
        self.member = member
        _draft = State(initialValue: member)
        _hasBirthday = State(initialValue: member.birthday != nil)
    }

    private var isNew: Bool { store.data.member(member.id) == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        MemberAvatar(member: FamilyMember(name: draft.name.isEmpty ? "?" : draft.name,
                                                          role: draft.role, color: draft.color), size: 72)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    TextField("Name", text: $draft.name)
                        .textContentType(.name)
                    Picker("Role", selection: $draft.role) {
                        ForEach(FamilyMember.Role.allCases) { r in
                            Text(r.label).tag(r)
                        }
                    }
                    Toggle("Birthday", isOn: $hasBirthday)
                    if hasBirthday {
                        DatePicker("Born", selection: Binding(
                            get: { draft.birthday ?? Date() },
                            set: { draft.birthday = $0 }), in: ...Date(), displayedComponents: .date)
                    }
                }
                Section("Colour") {
                    ColorChoice(selection: $draft.color)
                }
                if !isNew {
                    Section {
                        Button("Remove \(member.firstName)", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Their events, to-dos and expenses stay; they're just no longer tagged.")
                    }
                }
            }
            .navigationTitle(isNew ? "Add Person" : "Edit Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var saved = draft
                        saved.name = saved.name.trimmingCharacters(in: .whitespaces)
                        if !hasBirthday { saved.birthday = nil } else if saved.birthday == nil { saved.birthday = Date() }
                        store.save(saved)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Remove \(member.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    store.deleteMember(member.id)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Contacts

struct ContactsView: View {
    @EnvironmentObject var store: FamilyStore
    @State private var search = ""
    @State private var editing: Contact? = nil

    private var contacts: [Contact] {
        store.data.contacts
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.role.localizedCaseInsensitiveContains(search) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            if store.data.contacts.isEmpty {
                ContentUnavailableView("No contacts yet", systemImage: "person.crop.rectangle.stack",
                                       description: Text("Add the pediatrician, teachers, coaches and sitters."))
            }
            ForEach(contacts) { c in
                NavigationLink {
                    ContactDetailView(contactID: c.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name)
                        if !c.role.isEmpty { Text(c.role).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            .onDelete { offsets in
                let list = contacts
                for i in offsets { store.deleteContact(list[i].id) }
            }
        }
        .navigationTitle("Contacts")
        .searchable(text: $search)
        .toolbar {
            Button {
                editing = Contact(name: "")
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("New contact")
        }
        .sheet(item: $editing) { c in ContactEditor(original: c) }
    }
}

struct ContactDetailView: View {
    @EnvironmentObject var store: FamilyStore
    let contactID: UUID
    @State private var editing: Contact? = nil

    var body: some View {
        if let contact = store.data.contacts.first(where: { $0.id == contactID }) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(contact.name).font(.title2.bold())
                        if !contact.role.isEmpty { Text(contact.role).foregroundStyle(.secondary) }
                    }
                }
                Section {
                    if !contact.phone.isEmpty {
                        if let tel = URL(string: "tel:" + contact.phone.filter { $0.isNumber || $0 == "+" }) {
                            Link(destination: tel) { Label(contact.phone, systemImage: "phone") }
                        }
                        if let sms = URL(string: "sms:" + contact.phone.filter { $0.isNumber || $0 == "+" }) {
                            Link(destination: sms) { Label("Send a text", systemImage: "message") }
                        }
                    }
                    if !contact.email.isEmpty, let mail = URL(string: "mailto:" + contact.email) {
                        Link(destination: mail) { Label(contact.email, systemImage: "envelope") }
                    }
                }
                let people = store.data.members(contact.memberIDs)
                if !people.isEmpty {
                    Section("For") {
                        ForEach(people) { m in
                            HStack { MemberAvatar(member: m, size: 24); Text(m.name) }
                        }
                    }
                }
                if !contact.notes.isEmpty {
                    Section("Notes") { Text(contact.notes).textSelection(.enabled) }
                }
            }
            .toolbar { Button("Edit") { editing = contact } }
            .sheet(item: $editing) { c in ContactEditor(original: c) }
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Contact deleted", systemImage: "person.slash")
        }
    }
}

struct ContactEditor: View {
    @EnvironmentObject var store: FamilyStore
    @Environment(\.dismiss) var dismiss
    let original: Contact
    @State private var draft: Contact

    init(original: Contact) {
        self.original = original
        _draft = State(initialValue: original)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name).textContentType(.name)
                    TextField("Role — e.g. Pediatrician, Coach", text: $draft.role)
                }
                Section {
                    TextField("Phone", text: $draft.phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                    TextField("Email", text: $draft.email).keyboardType(.emailAddress)
                        .textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("For") {
                    MemberMultiPicker(members: store.data.children.isEmpty ? store.data.members : store.data.children,
                                      selection: $draft.memberIDs)
                }
                Section("Notes") {
                    TextField("Office hours, address, rates…", text: $draft.notes, axis: .vertical).lineLimit(2...8)
                }
                if store.data.contacts.contains(where: { $0.id == original.id }) {
                    Section {
                        Button("Delete Contact", role: .destructive) {
                            store.deleteContact(original.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(draft.name.isEmpty ? "New Contact" : draft.name)
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
        }
    }
}

// MARK: - Important info

struct InfoListView: View {
    @EnvironmentObject var store: FamilyStore
    let memberID: UUID?
    @State private var editing: InfoItem? = nil

    var body: some View {
        List {
            if store.data.info.isEmpty {
                ContentUnavailableView("Nothing saved yet", systemImage: "list.clipboard",
                                       description: Text("Shoe sizes, allergies, insurance numbers, the school's front-office number — keep them here."))
            }
            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items) { item in
                        Button { editing = item } label: { InfoRow(item: item) }
                            .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for i in offsets { store.deleteInfo(group.items[i].id) }
                    }
                }
            }
        }
        .navigationTitle("Important Info")
        .toolbar {
            Button {
                editing = InfoItem(memberID: memberID, category: .other, title: "", value: "")
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add info")
        }
        .sheet(item: $editing) { item in InfoEditor(original: item) }
    }

    struct InfoGroup {
        let title: String
        let items: [InfoItem]
    }

    private var groups: [InfoGroup] {
        let people: [FamilyMember?] = [nil] + store.data.members.map { Optional($0) }
        return people.compactMap { person -> InfoGroup? in
            let items = store.data.info.filter { $0.memberID == person?.id }
                .sorted { ($0.category.label, $0.title) < ($1.category.label, $1.title) }
            guard !items.isEmpty else { return nil }
            return InfoGroup(title: person?.name ?? "Whole family", items: items)
        }
    }
}

struct InfoRow: View {
    let item: InfoItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.category.symbol).foregroundStyle(.secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.semibold))
                Text(item.value).textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

struct InfoEditor: View {
    @EnvironmentObject var store: FamilyStore
    @Environment(\.dismiss) var dismiss
    let original: InfoItem
    @State private var draft: InfoItem

    init(original: InfoItem) {
        self.original = original
        _draft = State(initialValue: original)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Label — e.g. Shoe size", text: $draft.title)
                    TextField("Value", text: $draft.value, axis: .vertical).lineLimit(1...6)
                }
                Section {
                    Picker("Kind", selection: $draft.category) {
                        ForEach(InfoItem.Category.allCases) { c in
                            Label(c.label, systemImage: c.symbol).tag(c)
                        }
                    }
                    Picker("For", selection: $draft.memberID) {
                        Text("Whole family").tag(UUID?.none)
                        ForEach(store.data.members) { m in
                            Text(m.name).tag(UUID?.some(m.id))
                        }
                    }
                }
            }
            .navigationTitle(draft.title.isEmpty ? "New Info" : draft.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.save(draft)
                        dismiss()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
