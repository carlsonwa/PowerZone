import SwiftUI

/// Preview of a workout's profile, and the gate into the ride.
struct WorkoutDetailView: View {
    let entry: CatalogEntry
    @ObservedObject var client: HFBClient
    @ObservedObject var meter: PowerMeterService
    @ObservedObject var music: AppleMusicService

    @AppStorage("ftp") private var ftp: Double = 200
    @State private var workout: Workout?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        Group {
            if let workout {
                loaded(workout)
            } else if loading {
                ProgressView("Loading workout…")
            } else {
                ContentUnavailableView("Couldn't read this workout",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(error ?? "Unknown error"))
            }
        }
        .navigationTitle(entry.summary)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func loaded(_ workout: Workout) -> some View {
        VStack(spacing: 14) {
            PowerZoneChart(workout: workout, samples: [], elapsed: 0, ftp: ftp, isLive: false)
                .frame(height: 220)
                .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 20) {
                Label("\(entry.minutes) min", systemImage: "clock")
                Label(entry.instructor, systemImage: "person")
                Label("TSS \(entry.tss)", systemImage: "chart.bar")
                Spacer()
                Text("FTP \(Int(ftp)) W").foregroundStyle(.secondary)
            }
            .font(.subheadline)

            List {
                Section("Blocks") {
                    ForEach(workout.intervals) { interval in
                        HStack {
                            Circle()
                                .fill(PowerZones.color(zone: interval.zone.colorZone))
                                .frame(width: 10, height: 10)
                            Text(interval.zone.displayName)
                            Spacer()
                            if let segment = workout.targetSegment(at: interval.start) {
                                // A ramped block spans a range rather than sitting at one number.
                                Text(segment.isRamp
                                     ? "\(Int(segment.startWatts(ftp: ftp)))–\(Int(segment.endWatts(ftp: ftp))) W"
                                     : "\(Int(segment.startWatts(ftp: ftp))) W")
                                    .foregroundStyle(.secondary).monospacedDigit()
                            }
                            Text(format(interval.duration))
                                .monospacedDigit()
                                .frame(width: 60, alignment: .trailing)
                        }
                    }
                }
            }

            NavigationLink {
                RideView(workout: workout, meter: meter, music: music, ftp: ftp)
            } label: {
                Label(meter.isReceivingData ? "Start Ride" : "Start Ride (no meter connected)",
                      systemImage: "figure.outdoor.cycle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(meter.isReceivingData ? .green : .gray)
        }
        .padding()
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            workout = try await client.loadWorkout(entry)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func format(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
