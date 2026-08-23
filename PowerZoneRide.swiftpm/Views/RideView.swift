import SwiftUI

/// The screen you look at while riding.
///
/// Everything the website's timer shows is here — current zone, time left in it, the next
/// three blocks, total time remaining, and the ±1s/±10s sync nudges — plus the thing the
/// website can't do, which is your actual power drawn against the target.
struct RideView: View {
    @StateObject private var engine: RideEngine
    @ObservedObject var meter: PowerMeterService
    @ObservedObject var music: AppleMusicService
    @Environment(\.dismiss) private var dismiss

    @AppStorage("ftp") private var ftp: Double = 200
    @AppStorage("musicAutoStart") private var musicAutoStart = true
    @State private var showingSummary = false

    init(workout: Workout, meter: PowerMeterService, music: AppleMusicService, ftp: Double) {
        self.meter = meter
        self.music = music
        _engine = StateObject(wrappedValue: RideEngine(workout: workout, meter: meter, ftp: ftp))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 10) {
                header
                PowerZoneChart(workout: engine.workout,
                               samples: engine.displaySamples,
                               elapsed: engine.elapsed,
                               ftp: ftp)
                    .frame(maxHeight: .infinity)
                readout
                intervalStrip
                if showMusicBar { musicBar }
                controls
            }
            .padding(14)
        }
        .navigationBarBackButtonHidden(true)
        .statusBarHidden()
        .onChange(of: engine.phase) { _, phase in
            if phase == .finished { showingSummary = true }
        }
        .sheet(isPresented: $showingSummary) {
            RideSummaryView(engine: engine, ftp: ftp) { dismiss() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(engine.workout.title)
                    .font(.headline).foregroundStyle(.white)
                    .lineLimit(1)
                Text(engine.workout.instructor)
                    .font(.subheadline).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            connectionPill
            VStack(alignment: .trailing, spacing: 2) {
                Text(format(engine.remaining))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit().foregroundStyle(.white)
                Text("REMAINING")
                    .font(.caption2).foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private var connectionPill: some View {
        let ok = meter.isReceivingData
        return Label(ok ? "Meter" : meter.state.label,
                     systemImage: ok ? "bolt.horizontal.fill" : "bolt.horizontal")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background((ok ? Color.green : Color.orange).opacity(0.18), in: Capsule())
            .foregroundStyle(ok ? .green : .orange)
            .padding(.trailing, 12)
    }

    // MARK: - Live numbers

    private var readout: some View {
        HStack(spacing: 12) {
            metric(String(engine.smoothedWatts), "WATTS", big: true,
                   tint: PowerZones.color(zone: engine.currentZone))

            if let target = engine.targetWatts {
                metric("\(Int(target))", "TARGET")
                metric(deltaText(target), "DIFF", tint: deltaTint(target))
            }

            metric("\(meter.cadence)", "RPM")
            metric("Z\(engine.currentZone)", "YOUR ZONE",
                   tint: PowerZones.color(zone: engine.currentZone))
        }
    }

    private func metric(_ value: String, _ label: String,
                        big: Bool = false, tint: Color = .white) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: big ? 62 : 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(label)
                .font(.caption2).foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func deltaText(_ target: Double) -> String {
        let d = engine.smoothedWatts - Int(target)
        return d >= 0 ? "+\(d)" : "\(d)"
    }

    /// Green inside a ±10 W band, amber outside — enough to steer by without demanding
    /// precision the pedals can't deliver anyway.
    private func deltaTint(_ target: Double) -> Color {
        abs(Double(engine.smoothedWatts) - target) <= 10 ? .green : .orange
    }

    // MARK: - Intervals

    private var intervalStrip: some View {
        HStack(spacing: 10) {
            if let current = engine.currentInterval {
                intervalCard(zone: current.zone,
                             time: engine.secondsLeftInInterval,
                             caption: "NOW",
                             prominent: true)
            }
            ForEach(Array(engine.upcoming.enumerated()), id: \.element.id) { i, interval in
                intervalCard(zone: interval.zone,
                             time: interval.duration,
                             caption: i == 0 ? "NEXT" : "THEN",
                             prominent: false)
            }
            Spacer(minLength: 0)
        }
    }

    private func intervalCard(zone: ZoneCode, time: Int, caption: String,
                              prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption)
                .font(.caption2).foregroundStyle(.white.opacity(0.45))
            Text(zone.displayName)
                .font(prominent ? .title3.bold() : .subheadline.weight(.medium))
                .foregroundStyle(.white).lineLimit(1)
            Text(format(time))
                .font(prominent ? .title2.bold() : .subheadline)
                .monospacedDigit()
                .foregroundStyle(PowerZones.color(zone: zone.colorZone))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(minWidth: prominent ? 180 : 130, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(PowerZones.color(zone: zone.colorZone).opacity(prominent ? 0.28 : 0.12))
        )
    }

    // MARK: - Music

    /// Only worth the row when there is something to control: a track playing, or a
    /// playlist chosen in Settings that a tap can start.
    private var showMusicBar: Bool {
        music.state == .connected && (music.nowPlaying != nil || music.selectedPlaylist != nil)
    }

    private var musicBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "music.note")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))

            Text(music.nowPlaying.map { np in
                np.artist.isEmpty ? np.title : "\(np.title) — \(np.artist)"
            } ?? music.selectedPlaylist?.name ?? "")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)

            Spacer(minLength: 0)

            // Big enough to hit with a sweaty thumb without looking down.
            Button { music.skipToPrevious() } label: { Image(systemName: "backward.fill") }
            Button { music.togglePlayPause() } label: {
                Image(systemName: music.isPlaying ? "pause.fill" : "play.fill").frame(width: 20)
            }
            Button { music.skipToNext() } label: { Image(systemName: "forward.fill") }
        }
        .font(.title3)
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                if engine.phase == .running {
                    engine.pause()
                } else {
                    engine.start()
                    if musicAutoStart { music.startSelectedPlaylistIfIdle() }
                }
            } label: {
                Label(engine.phase == .running ? "Pause" : "Start",
                      systemImage: engine.phase == .running ? "pause.fill" : "play.fill")
                    .frame(width: 130)
            }
            .buttonStyle(.borderedProminent)
            .tint(engine.phase == .running ? .orange : .green)

            Spacer()

            // Manual sync: the class video has its own clock and no way to tell us where
            // it is, so these line the timer up by hand.
            Text("SYNC").font(.caption2).foregroundStyle(.white.opacity(0.45))
            ForEach([-10, -1, 1, 10], id: \.self) { delta in
                Button(delta > 0 ? "+\(delta)" : "\(delta)") { engine.nudge(delta) }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .monospacedDigit()
            }

            Spacer()

            Button("End Ride", role: .destructive) { engine.finish() }
                .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }

    private func format(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
