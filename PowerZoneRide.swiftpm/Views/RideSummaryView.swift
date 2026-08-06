import SwiftUI

/// Post-ride numbers, plus the two ways a ride leaves the iPad.
struct RideSummaryView: View {
    @ObservedObject var engine: RideEngine
    let ftp: Double
    let onDone: () -> Void

    @State private var exportURL: URL?
    @State private var healthState: String?
    @State private var startedAt = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    stats
                    zoneBreakdown
                    exportButtons
                    if let healthState {
                        Text(healthState)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
            }
            .navigationTitle("Ride Complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
        .onAppear {
            // The ride started `samples.count` seconds ago.
            startedAt = Date().addingTimeInterval(-Double(engine.samples.count))
        }
    }

    private var stats: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
            stat("\(engine.averageWatts)", "Avg Watts")
            stat("\(engine.normalizedWatts)", "Normalized")
            stat(String(format: "%.2f", engine.intensityFactor), "Intensity")
            stat("\(engine.trainingStressScore)", "TSS")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    private var zoneBreakdown: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Time in Zones").font(.headline)
            ForEach(1...7, id: \.self) { z in
                let seconds = engine.timeInZones[z] ?? 0
                if seconds > 0 {
                    HStack {
                        Text("Zone \(z)").font(.subheadline)
                            .frame(width: 70, alignment: .leading)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(PowerZones.color(zone: z))
                                .frame(width: geo.size.width * barFraction(seconds))
                        }
                        .frame(height: 16)
                        Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                            .font(.subheadline).monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func barFraction(_ seconds: Int) -> Double {
        let peak = engine.timeInZones.values.max() ?? 1
        return peak > 0 ? Double(seconds) / Double(peak) : 0
    }

    private var exportButtons: some View {
        VStack(spacing: 10) {
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Share TCX File", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    exportURL = try? TCXExporter.write(engine: engine, startedAt: startedAt)
                    if exportURL == nil { healthState = "Couldn't write the TCX file." }
                } label: {
                    Label("Export TCX", systemImage: "doc.badge.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                Task { await saveToHealth() }
            } label: {
                Label("Save to Apple Health", systemImage: "heart.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }

    private func saveToHealth() async {
        switch await HealthKitExporter.requestAuthorization() {
        case .unsupported:
            healthState = "Health isn't available on this device. Use the TCX export instead."
        case .notAuthorized:
            healthState = """
                Health access wasn't granted. Apps built in Swift Playgrounds can't request \
                the HealthKit entitlement — use the TCX export, which imports into Strava, \
                TrainingPeaks and Garmin Connect.
                """
        case .available:
            do {
                try await HealthKitExporter.save(engine: engine, startedAt: startedAt)
                healthState = "Saved to Apple Health."
            } catch {
                healthState = "Health save failed: \(error.localizedDescription). Use the TCX export."
            }
        }
    }
}
