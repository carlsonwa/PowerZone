import SwiftUI

/// Runs the parsers against saved copies of real pages and reports pass/fail.
///
/// Swift Playgrounds has no XCTest target, so this stands in for a unit test suite: it is
/// the same fixtures `tools/verify_parsers.py` checks, run through the Swift code on the
/// device that actually matters. When workouts stop loading, this answers "did the site
/// change, or is it my network?" without a Mac in the loop.
struct ParserSelfTestView: View {
    @State private var results: [Result] = []
    @State private var running = false

    struct Result: Identifiable {
        let id = UUID()
        let name: String
        let passed: Bool
        let detail: String
    }

    /// Fixture id -> the values `tools/verify_parsers.py` recorded for it.
    ///
    /// Workout 2 is the one that matters most: it is an older class whose warm-up ramps
    /// rather than stepping, which a flat-block model silently drops. `ramps` is asserted
    /// so that case can't regress unnoticed.
    private static let expected: [(id: Int, intervals: Int, classLength: Int, segments: Int, ramps: Int)] = [
        (2, 13, 2700, 14, 2),
        (375, 23, 1200, 23, 0),
        (864, 12, 1800, 16, 0),
        (851, 45, 3600, 51, 0),
        (1595, 38, 3600, 38, 0)
    ]

    var body: some View {
        List {
            Section {
                Button {
                    run()
                } label: {
                    HStack {
                        Text(running ? "Running…" : "Run Self-Test")
                        if running { Spacer(); ProgressView() }
                    }
                }
                .disabled(running)
            }

            if !results.isEmpty {
                Section(summary) {
                    ForEach(results) { r in
                        HStack(alignment: .top) {
                            Image(systemName: r.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(r.passed ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).font(.subheadline.weight(.medium))
                                Text(r.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Parser Self-Test")
    }

    private var summary: String {
        let passed = results.filter(\.passed).count
        return "\(passed)/\(results.count) passed"
    }

    private func run() {
        running = true
        var out: [Result] = []

        for e in Self.expected {
            let name = "workout_\(e.id).html"
            guard let html = fixture(name) else {
                out.append(Result(name: name, passed: false, detail: "Fixture missing from the bundle"))
                continue
            }
            do {
                let w = try WorkoutParser.parse(html: html, id: e.id)
                var problems: [String] = []
                if w.intervals.count != e.intervals {
                    problems.append("expected \(e.intervals) intervals, got \(w.intervals.count)")
                }
                if w.classLength != e.classLength {
                    problems.append("expected \(e.classLength)s, got \(w.classLength)s")
                }
                // The segments must tile the class exactly. This is the check that catches
                // a reordered curve or a dropped warm-up ramp — both of which still parse
                // cleanly but draw the wrong target.
                let segments = w.targetSegments
                let covered = segments.reduce(0) { $0 + ($1.end - $1.start) }
                if covered != w.classLength {
                    problems.append("target segments cover \(covered)s of \(w.classLength)s")
                }
                if let broken = zip(segments, segments.dropFirst()).first(where: { $0.end != $1.start }) {
                    problems.append("segments break at \(broken.0.end)s")
                }
                if segments.count != e.segments {
                    problems.append("expected \(e.segments) segments, got \(segments.count)")
                }
                let ramps = segments.filter(\.isRamp).count
                if ramps != e.ramps {
                    problems.append("expected \(e.ramps) ramps, got \(ramps)")
                }
                out.append(Result(
                    name: name,
                    passed: problems.isEmpty,
                    detail: problems.isEmpty
                        ? "\(w.intervals.count) intervals, \(segments.count) segments"
                            + (ramps > 0 ? " (\(ramps) ramped)" : "")
                            + ", \(w.classLength / 60) min"
                        : problems.joined(separator: "; ")
                ))
            } catch {
                out.append(Result(name: name, passed: false, detail: error.localizedDescription))
            }
        }

        if let html = fixture("catalog_sample.html") {
            let entries = CatalogParser.parse(html: html)
            out.append(Result(
                name: "catalog_sample.html",
                passed: entries.count >= 40,
                detail: entries.isEmpty
                    ? "No rows parsed — the library page format changed"
                    : "\(entries.count) rows, newest: \(entries[0].summary)"
            ))
        } else {
            out.append(Result(name: "catalog_sample.html", passed: false, detail: "Fixture missing"))
        }

        results = out
        running = false
    }

    /// SwiftPM normally routes target resources to `Bundle.module`, but a `.swiftpm` app
    /// module is also the main bundle, and the copied folder may or may not survive as a
    /// subdirectory. Rather than guess, try each combination.
    private func fixture(_ name: String) -> String? {
        let base = (name as NSString).deletingPathExtension
        let bundles = [Bundle.module, Bundle.main]
        for bundle in bundles {
            if let url = bundle.url(forResource: base, withExtension: "html", subdirectory: "Fixtures")
                ?? bundle.url(forResource: base, withExtension: "html") {
                return try? String(contentsOf: url, encoding: .utf8)
            }
        }
        return nil
    }
}
