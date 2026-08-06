import SwiftUI

/// Browse the homefitnessbuddy workout library.
///
/// The whole catalog — around 1,500 classes — arrives in one request and is filtered
/// locally, so scrubbing the filters is instant and costs the site nothing.
struct LibraryView: View {
    @ObservedObject var client: HFBClient
    @ObservedObject var meter: PowerMeterService

    @State private var search = ""
    @State private var instructor: String?
    @State private var duration: Int?
    @State private var typeCode: String?

    var body: some View {
        List {
            if client.isLoadingCatalog && client.catalog.isEmpty {
                HStack { ProgressView(); Text("Loading library…").foregroundStyle(.secondary) }
            }
            if let error = client.catalogError, client.catalog.isEmpty {
                ContentUnavailableView("Couldn't load the library", systemImage: "wifi.exclamationmark",
                                       description: Text(error))
            }

            ForEach(filtered) { entry in
                NavigationLink(value: entry) {
                    row(entry)
                }
            }
        }
        .navigationTitle("Power Zone Library")
        .searchable(text: $search, prompt: "Instructor, class type, date")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { filterMenu }
        }
        .refreshable { await client.loadCatalog(forceRefresh: true) }
        .task { await client.loadCatalog() }
        .navigationDestination(for: CatalogEntry.self) { entry in
            WorkoutDetailView(entry: entry, client: client, meter: meter)
        }
    }

    private func row(_ entry: CatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(entry.summary).font(.headline)
                if client.isCached(entry.id) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
            }
            Text(entry.instructor).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(entry.displayDate)
                Text("TSS \(entry.tss)")
                ForEach(entry.zoneList, id: \.self) { z in
                    Text(z)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(zoneTint(z).opacity(0.25), in: Capsule())
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func zoneTint(_ label: String) -> Color {
        PowerZones.color(zone: Int(label.dropFirst()) ?? 1)
    }

    private var filterMenu: some View {
        Menu {
            Picker("Duration", selection: $duration) {
                Text("Any length").tag(Int?.none)
                ForEach(durations, id: \.self) { Text("\($0) min").tag(Int?.some($0)) }
            }
            Picker("Instructor", selection: $instructor) {
                Text("All instructors").tag(String?.none)
                ForEach(instructors, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            Picker("Class type", selection: $typeCode) {
                Text("All types").tag(String?.none)
                ForEach(typeCodes, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            if isFiltered {
                Divider()
                Button("Clear filters", role: .destructive) {
                    duration = nil; instructor = nil; typeCode = nil
                }
            }
        } label: {
            Label("Filter", systemImage: isFiltered
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
    }

    private var isFiltered: Bool { duration != nil || instructor != nil || typeCode != nil }

    private var durations: [Int] {
        Array(Set(client.catalog.map(\.minutes))).filter { $0 > 0 }.sorted()
    }
    private var instructors: [String] {
        Array(Set(client.catalog.map(\.instructor))).filter { !$0.isEmpty }.sorted()
    }
    private var typeCodes: [String] {
        Array(Set(client.catalog.map(\.typeCode))).filter { !$0.isEmpty }.sorted()
    }

    private var filtered: [CatalogEntry] {
        client.catalog.filter { e in
            if let duration, e.minutes != duration { return false }
            if let instructor, e.instructor != instructor { return false }
            if let typeCode, e.typeCode != typeCode { return false }
            if !search.isEmpty {
                let hay = "\(e.instructor) \(e.typeName) \(e.typeCode) \(e.displayDate) \(e.title)"
                if !hay.localizedCaseInsensitiveContains(search) { return false }
            }
            return true
        }
    }
}
