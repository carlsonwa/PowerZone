import SwiftUI

/// Connect Apple Music and pick the playlist a ride starts with.
///
/// Deliberately shaped like `MeterConnectionView`: status at the top, the things you can
/// connect to below it, and everything you need to confirm it works before you're on the
/// bike and can't fiddle with it.
struct MusicConnectionView: View {
    @ObservedObject var music: AppleMusicService
    @AppStorage("musicAutoStart") private var autoStart = true

    var body: some View {
        List {
            Section {
                HStack {
                    Text(music.state.label)
                    Spacer()
                    if music.isPlaying {
                        Label("Playing", systemImage: "waveform")
                            .font(.caption).foregroundStyle(.green)
                    }
                }

                switch music.state {
                case .notConnected, .connecting:
                    Button("Connect Apple Music") { music.connect() }
                        .disabled(music.state == .connecting)
                case .denied:
                    if let url = music.systemSettingsURL {
                        Link("Open iPad Settings", destination: url)
                    }
                default:
                    EmptyView()
                }

                if let error = music.lastError {
                    Text(error).font(.footnote).foregroundStyle(.orange)
                }
            } header: {
                Text("Status")
            } footer: {
                Text(footerText)
            }

            if music.state == .connected {
                nowPlayingSection
                optionsSection
                playlistSection
            }
        }
        .navigationTitle("Apple Music")
        // Deliberately not `connect()`: the system prompt should follow the button, not
        // ambush someone who opened this screen to see what it does.
        .task {
            music.start()
            await music.loadPlaylists()
        }
    }

    private var footerText: String {
        switch music.state {
        case .denied:
            return "Access was declined. Turn Media & Apple Music back on for PowerZone Ride in iPad Settings → Privacy & Security."
        case .restricted:
            return "Access to the media library is restricted on this iPad, most likely by Screen Time."
        case .unavailable:
            return "This build has no Apple Music usage description, so it can't ask for access. Enable Apple Music under App Settings → Capabilities in Swift Playgrounds and run the app again."
        default:
            return "Playback runs through the Music app, so it keeps going when the screen locks or you switch apps — and starting a playlist here replaces whatever Music was playing."
        }
    }

    // MARK: - Now playing

    @ViewBuilder
    private var nowPlayingSection: some View {
        Section("Now Playing") {
            HStack(spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(music.nowPlaying?.title ?? "Nothing playing")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(music.nowPlaying?.artist ?? music.selectedPlaylist?.name ?? "Pick a playlist below")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                transport
            }
            .padding(.vertical, 2)
        }
    }

    private var artwork: some View {
        Group {
            if let image = music.nowPlaying?.artwork {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.15)
                    Image(systemName: "music.note").foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var transport: some View {
        HStack(spacing: 18) {
            Button { music.skipToPrevious() } label: {
                Image(systemName: "backward.fill")
            }
            Button { music.togglePlayPause() } label: {
                Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 22)
            }
            Button { music.skipToNext() } label: {
                Image(systemName: "forward.fill")
            }
        }
        .font(.title3)
        // A Form row sends a tap to the whole row unless each button opts out.
        .buttonStyle(.borderless)
    }

    // MARK: - Options

    private var optionsSection: some View {
        Section {
            Toggle("Shuffle", isOn: $music.shuffle)
            Toggle("Start with the ride", isOn: $autoStart)
        } footer: {
            Text("With this on, tapping Start on the ride screen starts the chosen playlist — unless music is already playing, which is left alone.")
        }
    }

    // MARK: - Playlists

    @ViewBuilder
    private var playlistSection: some View {
        Section {
            if music.isLoadingPlaylists && music.playlists.isEmpty {
                HStack { ProgressView(); Text("Reading your library…").foregroundStyle(.secondary) }
            } else if music.playlists.isEmpty {
                Text("No playlists in your library")
                    .foregroundStyle(.secondary)
            }

            ForEach(music.playlists) { playlist in
                Button {
                    music.play(playlist)
                } label: {
                    HStack {
                        Image(systemName: music.selectedPlaylist?.id == playlist.id
                              ? "checkmark.circle.fill" : "music.note.list")
                            .foregroundStyle(music.selectedPlaylist?.id == playlist.id ? .green : .secondary)
                        Text(playlist.name).lineLimit(1)
                        Spacer()
                        Text("\(playlist.count)")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .tint(.primary)
            }
        } header: {
            Text("Playlists")
        } footer: {
            Text("Tapping a playlist starts it now and remembers it for your next ride.")
        }
    }
}
