import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: FamilyStore
    @AppStorage("currencyCode") private var currencyCode: String = Locale.current.currency?.identifier ?? "USD"
    @State private var notificationsOn = false
    @State private var confirmSample = false
    @State private var confirmErase = false
    @State private var importing = false
    @State private var pendingImport: FamilyData? = nil
    @State private var importError: String? = nil

    private let currencies = ["USD", "CAD", "EUR", "GBP", "AUD", "NZD", "CHF", "JPY", "INR", "MXN", "SEK", "NOK", "DKK", "ZAR", "SGD"]

    var body: some View {
        Form {
            Section {
                Picker("Currency", selection: $currencyCode) {
                    ForEach(currencyOptions, id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
            }

            Section {
                if notificationsOn {
                    Label("Reminders are on", systemImage: "bell.badge")
                } else {
                    Button {
                        Task {
                            _ = await ReminderScheduler.requestPermission()
                            notificationsOn = await ReminderScheduler.isAuthorized()
                            store.saveNow()
                        }
                    } label: {
                        Label("Turn On Reminders", systemImage: "bell")
                    }
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Event and to-do reminders are scheduled on this device. If you turned them off before, switch them back on in the Settings app under Kinboard.")
            }

            Section {
                NavigationLink {
                    ExportView()
                } label: {
                    Label("Export & Back Up", systemImage: "square.and.arrow.up")
                }
                Button {
                    importing = true
                } label: {
                    Label("Restore from Backup…", systemImage: "arrow.down.doc")
                }
            } header: {
                Text("Your data")
            } footer: {
                Text("Everything is stored only on this device. Make a backup now and then — and before deleting the app.")
            }

            Section {
                Button {
                    confirmSample = true
                } label: {
                    Label("Load Sample Family", systemImage: "person.3")
                }
                Button(role: .destructive) {
                    confirmErase = true
                } label: {
                    Label("Erase All Data", systemImage: "trash")
                }
            }

            Section {
                NavigationLink {
                    SelfCheckView()
                } label: {
                    Label("Run Self-Check", systemImage: "checkmark.seal")
                }
            } footer: {
                Text("Checks repeats, reminders, money and message reading on this device. Worth running if dates from messages ever look wrong.")
            }

            Section {
                LabeledContent("People", value: "\(store.data.members.count)")
                LabeledContent("Events", value: "\(store.data.events.count)")
                LabeledContent("To-dos", value: "\(store.data.tasks.count)")
                LabeledContent("Expenses", value: "\(store.data.expenses.count)")
                LabeledContent("Tracker entries", value: "\(store.data.trackerEntries.count)")
                LabeledContent("Messages", value: "\(store.data.messages.count)")
            } header: {
                Text("About")
            } footer: {
                Text("Kinboard 1.0")
            }
        }
        .navigationTitle("Settings")
        .task { notificationsOn = await ReminderScheduler.isAuthorized() }
        .confirmationDialog("Replace everything with the sample family?", isPresented: $confirmSample, titleVisibility: .visible) {
            Button("Replace with Sample", role: .destructive) { store.loadSample() }
        } message: {
            Text("Your current data will be erased. Back it up first if you want to keep it.")
        }
        .confirmationDialog("Erase all of Kinboard's data?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase Everything", role: .destructive) { store.eraseEverything() }
        } message: {
            Text("This can't be undone.")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                readBackup(url)
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .alert("Restore this backup?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })) {
            Button("Replace My Data", role: .destructive) {
                if let data = pendingImport { store.replaceAll(with: data) }
                pendingImport = nil
            }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: {
            if let data = pendingImport {
                Text("It has \(data.members.count) people, \(data.events.count) events, \(data.tasks.count) to-dos and \(data.expenses.count) expenses. Everything currently in Kinboard will be replaced.")
            }
        }
        .alert("Couldn't restore", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    private var currencyOptions: [String] {
        currencies.contains(currencyCode) ? currencies : [currencyCode] + currencies
    }

    private func readBackup(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let raw = try Data(contentsOf: url)
            pendingImport = try FamilyData.decoder().decode(FamilyData.self, from: raw)
        } catch {
            importError = "That file isn't a Kinboard backup. (\(error.localizedDescription))"
        }
    }
}

/// Writes the export files when opened, then offers each through the share sheet.
struct ExportView: View {
    @EnvironmentObject var store: FamilyStore
    @State private var files: [ExportFile] = []
    @State private var error: String? = nil

    struct ExportFile: Identifiable {
        let title: String
        let detail: String
        let symbol: String
        let url: URL
        var id: URL { url }
    }

    var body: some View {
        List {
            if let error {
                Text(error).foregroundStyle(.red)
            }
            ForEach(files) { file in
                ShareLink(item: file.url) {
                    HStack(spacing: 12) {
                        Image(systemName: file.symbol).font(.title3).frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.title).foregroundStyle(.primary)
                            Text(file.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Export & Back Up")
        .task { prepare() }
    }

    private func prepare() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("KinboardExport", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = DayKey.make(Date(), calendar: store.calendar)
        let data = store.data
        let cal = store.calendar
        do {
            let backup = folder.appendingPathComponent("Kinboard Backup \(stamp).json")
            try store.backupData().write(to: backup)
            let ics = folder.appendingPathComponent("Kinboard Calendar.ics")
            try ICSExporter.calendar(data.events, members: data.members, calendar: cal).write(to: ics, atomically: true, encoding: .utf8)
            let expenses = folder.appendingPathComponent("Kinboard Expenses \(stamp).csv")
            try CSVExporter.expenses(data.expenses, members: data.members, calendar: cal).write(to: expenses, atomically: true, encoding: .utf8)
            let trackers = folder.appendingPathComponent("Kinboard Trackers \(stamp).csv")
            try CSVExporter.trackerEntries(data, calendar: cal).write(to: trackers, atomically: true, encoding: .utf8)
            files = [
                ExportFile(title: "Full backup", detail: "Everything, to restore later or on a new device. Save it to Files or iCloud Drive.",
                           symbol: "externaldrive", url: backup),
                ExportFile(title: "Calendar (.ics)", detail: "\(data.events.count) events with their repeats, for Apple, Google or Outlook Calendar.",
                           symbol: "calendar", url: ics),
                ExportFile(title: "Expenses (.csv)", detail: "\(data.expenses.count) expenses for a spreadsheet, taxes or FSA claims.",
                           symbol: "tablecells", url: expenses),
                ExportFile(title: "Tracker log (.csv)", detail: "\(data.trackerEntries.count) entries — handy for the pediatrician.",
                           symbol: "waveform.path.ecg", url: trackers),
            ]
        } catch {
            self.error = "Couldn't prepare the export: \(error.localizedDescription)"
        }
    }
}

struct SelfCheckView: View {
    @State private var results: [SelfChecks.Result] = []

    var body: some View {
        List {
            if !results.isEmpty {
                Section {
                    let failed = results.filter { !$0.passed }.count
                    Label(failed == 0 ? "All \(results.count) checks passed" : "\(failed) of \(results.count) checks failed",
                          systemImage: failed == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(failed == 0 ? Color.green : Color.orange)
                }
            }
            Section {
                ForEach(results) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(r.name, systemImage: r.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(r.passed ? Color.primary : Color.red)
                        if !r.detail.isEmpty {
                            Text(r.detail).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
            } footer: {
                Text("Message-reading checks use this device's own date detection, which can read a sentence differently from one iOS version or language to the next. A failure there means suggestions may need a closer look, not that your data is at risk.")
            }
        }
        .navigationTitle("Self-Check")
        .task {
            results = SelfChecks.run(detector: AppleDateDetector(), detectorCalendar: Calendar.current)
        }
    }
}
