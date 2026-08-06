import Foundation

/// Fetches workout data from homefitnessbuddy.
///
/// Everything happens on the iPad — there is no backend and nothing is republished. The
/// app requests exactly the pages a browser would, then caches hard: the catalog for a
/// day, individual workouts forever (a past class never changes). That keeps the load on
/// someone else's free tool close to nil and means a ride never depends on the network.
@MainActor
final class HFBClient: ObservableObject {
    @Published private(set) var catalog: [CatalogEntry] = []
    @Published private(set) var isLoadingCatalog = false
    @Published private(set) var catalogError: String?

    /// `nonisolated` so `@StateObject private var client = HFBClient()` can be written in
    /// a property initializer, which is not itself main-actor isolated.
    nonisolated init() {}

    private let base = "https://app.homefitnessbuddy.com/peloton/powerzone"
    private let catalogTTL: TimeInterval = 60 * 60 * 24
    private var workoutMemo: [Int: Workout] = [:]

    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        c.httpAdditionalHeaders = ["User-Agent": "PowerZoneRide/1.0 (personal use; iPadOS)"]
        return URLSession(configuration: c)
    }()

    private var cacheDir: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("hfb", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Catalog

    func loadCatalog(forceRefresh: Bool = false) async {
        if !catalog.isEmpty && !forceRefresh { return }
        isLoadingCatalog = true
        catalogError = nil
        defer { isLoadingCatalog = false }

        let cacheURL = cacheDir.appendingPathComponent("catalog.html")

        if !forceRefresh, let cached = readCache(cacheURL, maxAge: catalogTTL) {
            let parsed = CatalogParser.parse(html: cached)
            if !parsed.isEmpty {
                catalog = parsed
                return
            }
        }

        do {
            let html = try await fetch("\(base)/")
            let parsed = CatalogParser.parse(html: html)
            guard !parsed.isEmpty else {
                throw ParseError.inconsistent("the library page had no readable rows")
            }
            try? html.write(to: cacheURL, atomically: true, encoding: .utf8)
            catalog = parsed
        } catch {
            // A stale catalog beats an empty screen — the library barely changes.
            if let stale = readCache(cacheURL, maxAge: .infinity) {
                catalog = CatalogParser.parse(html: stale)
                catalogError = catalog.isEmpty ? error.localizedDescription : nil
            } else {
                catalogError = error.localizedDescription
            }
        }
    }

    // MARK: - Workouts

    func loadWorkout(_ entry: CatalogEntry) async throws -> Workout {
        if let memo = workoutMemo[entry.id] { return memo }

        let cacheURL = cacheDir.appendingPathComponent("workout_\(entry.id).html")

        // A class that already aired is immutable, so any cached copy is good forever.
        if let cached = readCache(cacheURL, maxAge: .infinity),
           let workout = try? WorkoutParser.parse(html: cached, id: entry.id,
                                                  fallbackTitle: entry.summary,
                                                  fallbackInstructor: entry.instructor) {
            workoutMemo[entry.id] = workout
            return workout
        }

        let html = try await fetch("\(base)/details/\(entry.id)")
        let workout = try WorkoutParser.parse(html: html, id: entry.id,
                                              fallbackTitle: entry.summary,
                                              fallbackInstructor: entry.instructor)
        try? html.write(to: cacheURL, atomically: true, encoding: .utf8)
        workoutMemo[entry.id] = workout
        return workout
    }

    /// True when the workout can start without a network round-trip.
    func isCached(_ id: Int) -> Bool {
        workoutMemo[id] != nil
            || FileManager.default.fileExists(atPath: cacheDir.appendingPathComponent("workout_\(id).html").path)
    }

    // MARK: - Plumbing

    private func fetch(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw URLError(.cannotDecodeContentData)
        }
        return html
    }

    private func readCache(_ url: URL, maxAge: TimeInterval) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date,
              maxAge == .infinity || Date().timeIntervalSince(modified) < maxAge
        else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
