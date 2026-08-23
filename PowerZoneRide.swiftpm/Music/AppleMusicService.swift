import Combine
import Foundation
import MediaPlayer
import UIKit

/// Connects to Apple Music and drives playback for the ride.
///
/// This uses Media Player's *system* music player rather than MusicKit, and both halves of
/// that choice are forced by what a Swift Playgrounds app project can declare:
///
/// - MusicKit's catalog requests need a developer token issued against a MusicKit-enabled
///   App ID. This project has no team identifier, so that token can't exist — the same
///   wall the Health export runs into. `MPMediaLibrary` needs nothing but the usage
///   description in `Package.swift`.
/// - `MPMusicPlayerController.applicationMusicPlayer` keeps its own private queue, but it
///   needs the `audio` background mode to survive the screen locking or you switching
///   apps, and the manifest has no way to declare background modes. The system player is
///   the Music app's queue, playing on the Music app's audio session, so it keeps going
///   regardless of what this app is doing.
///
/// The trade-off of the system player is that the queue is shared: starting a playlist
/// here replaces whatever Music was playing, exactly as pressing play in Music would, and
/// music you start in the Music app shows up here without being started from this screen.
@MainActor
final class AppleMusicService: ObservableObject {

    enum ConnectionState: Equatable {
        case notConnected, connecting, connected, denied, restricted, unavailable

        var label: String {
            switch self {
            case .notConnected: return "Not connected"
            case .connecting:   return "Connecting…"
            case .connected:    return "Connected"
            case .denied:       return "Access denied"
            case .restricted:   return "Access restricted"
            case .unavailable:  return "Unavailable in this build"
            }
        }
    }

    /// A playlist as the picker needs it — the library objects themselves are heavy and
    /// tied to the media query, so only what's drawn is kept.
    struct PlaylistRef: Identifiable, Equatable, Sendable {
        let id: UInt64          // MPMediaEntityPersistentID
        let name: String
        let count: Int
    }

    struct NowPlaying: Equatable {
        let title: String
        let artist: String
        let artwork: UIImage?
    }

    @Published private(set) var state: ConnectionState = .notConnected
    @Published private(set) var playlists: [PlaylistRef] = []
    @Published private(set) var isLoadingPlaylists = false
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var isPlaying = false
    @Published private(set) var lastError: String?

    /// Chosen in Settings and remembered across launches, so a ride can start the music
    /// without taking your hands off the bars.
    @Published private(set) var selectedPlaylist: PlaylistRef?

    @Published var shuffle: Bool = UserDefaults.standard.bool(forKey: "musicShuffle") {
        didSet {
            UserDefaults.standard.set(shuffle, forKey: "musicShuffle")
            guard state == .connected else { return }
            player.shuffleMode = shuffle ? .songs : .off
        }
    }

    private let player = MPMusicPlayerController.systemMusicPlayer
    private var observers: [NSObjectProtocol] = []
    private var started = false

    /// `nonisolated` so this can be built in a `@StateObject` property initializer, the
    /// same way `PowerMeterService` is. Only stored properties are touched here.
    nonisolated init() {}

    // MARK: - Lifecycle

    /// Picks up the current authorization state and starts listening for playback changes.
    /// Called from the app's `.task`; safe to call more than once.
    func start() {
        guard !started else { return }
        started = true

        guard hasUsageDescription else {
            // iOS terminates an app that touches the media library without a usage
            // description, so this is a guard against a crash, not a nicety.
            state = .unavailable
            lastError = "This build can't ask for Apple Music access. Enable Apple Music under App Settings → Capabilities in Swift Playgrounds, then run again."
            return
        }

        player.beginGeneratingPlaybackNotifications()
        observe(MPMusicPlayerController.nowPlayingItemDidChangeNotification)
        observe(MPMusicPlayerController.playbackStateDidChangeNotification)

        applyAuthorization(MPMediaLibrary.authorizationStatus(), requestIfNeeded: false)
    }

    private func observe(_ name: Notification.Name) {
        let token = NotificationCenter.default.addObserver(
            forName: name,
            object: player,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshNowPlaying() }
        }
        observers.append(token)
    }

    /// The media library is only reachable when `NSAppleMusicUsageDescription` is present,
    /// which `.mediaLibrary(purposeString:)` in the manifest puts there.
    private var hasUsageDescription: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSAppleMusicUsageDescription") != nil
    }

    // MARK: - Connecting

    /// Ask for library access. Does nothing if already connected.
    func connect() {
        guard state != .connected else { return }
        guard hasUsageDescription else { state = .unavailable; return }
        applyAuthorization(MPMediaLibrary.authorizationStatus(), requestIfNeeded: true)
    }

    private func applyAuthorization(_ status: MPMediaLibraryAuthorizationStatus,
                                    requestIfNeeded: Bool) {
        switch status {
        case .authorized:
            state = .connected
            lastError = nil
            player.shuffleMode = shuffle ? .songs : .off
            restoreSelection()
            refreshNowPlaying()
            Task { await loadPlaylists() }

        case .notDetermined:
            guard requestIfNeeded else {
                state = .notConnected
                return
            }
            state = .connecting
            MPMediaLibrary.requestAuthorization { [weak self] status in
                Task { @MainActor in
                    self?.applyAuthorization(status, requestIfNeeded: false)
                }
            }

        case .denied:
            state = .denied
        case .restricted:
            state = .restricted
        @unknown default:
            state = .notConnected
        }
    }

    /// Where to send someone who declined the prompt — it can only be undone in Settings.
    var systemSettingsURL: URL? { URL(string: UIApplication.openSettingsURLString) }

    // MARK: - Playlists

    /// Reads the library's playlists. Done off the main actor because a large library
    /// makes this a disk read, and it runs while the library screen is on screen.
    func loadPlaylists() async {
        guard state == .connected else { return }
        isLoadingPlaylists = true
        defer { isLoadingPlaylists = false }

        playlists = await Task.detached(priority: .userInitiated) { () -> [PlaylistRef] in
            let query = MPMediaQuery.playlists()
            let collections = query.collections ?? []
            return collections.compactMap { collection -> PlaylistRef? in
                guard let name = collection.value(forProperty: MPMediaPlaylistPropertyName) as? String,
                      let id = (collection.value(forProperty: MPMediaPlaylistPropertyPersistentID) as? NSNumber)?.uint64Value,
                      collection.count > 0    // folders and emptied playlists have nothing to play
                else { return nil }
                return PlaylistRef(id: id, name: name, count: collection.count)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }.value

        // The remembered selection is restored from a name and an ID alone, so this is
        // where it picks up its track count — or is dropped, if the playlist is gone.
        if let selected = selectedPlaylist {
            if let live = playlists.first(where: { $0.id == selected.id }) {
                selectedPlaylist = live
            } else {
                clearSelection()
            }
        }
    }

    // MARK: - Playback

    /// Choose a playlist and start it. This is what tapping a playlist in Settings does.
    func play(_ playlist: PlaylistRef) {
        guard state == .connected else { return }
        select(playlist)
        startQueue(playlist)
    }

    /// Start the remembered playlist, unless music is already playing — used when a ride
    /// starts, where interrupting a song you already had going would be rude.
    func startSelectedPlaylistIfIdle() {
        guard state == .connected, !isPlaying, let playlist = selectedPlaylist else { return }
        startQueue(playlist)
    }

    private func startQueue(_ playlist: PlaylistRef) {
        guard let collection = collection(for: playlist.id) else {
            lastError = "“\(playlist.name)” is no longer in your library."
            clearSelection()
            return
        }
        lastError = nil
        player.setQueue(with: collection)
        player.shuffleMode = shuffle ? .songs : .off
        player.repeatMode = .all   // a 45-minute class outlasts most playlists

        // The system player hands its queue to the Music app; playing before it has taken
        // it can silently do nothing, so wait to be told it's ready.
        player.prepareToPlay { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.lastError = error.localizedDescription
                    return
                }
                self.player.play()
                self.refreshNowPlaying()
            }
        }
    }

    func togglePlayPause() {
        guard state == .connected else { return }
        if player.playbackState == .playing {
            player.pause()
        } else if player.nowPlayingItem != nil {
            player.play()
        } else if let playlist = selectedPlaylist {
            startQueue(playlist)
        }
        refreshNowPlaying()
    }

    func skipToNext() {
        guard state == .connected else { return }
        player.skipToNextItem()
    }

    /// Back through the track the way every music app does it: restart the current song
    /// unless you're still near its start.
    func skipToPrevious() {
        guard state == .connected else { return }
        if player.currentPlaybackTime > 3 {
            player.skipToBeginning()
        } else {
            player.skipToPreviousItem()
        }
    }

    private func collection(for id: UInt64) -> MPMediaItemCollection? {
        let query = MPMediaQuery.playlists()
        query.addFilterPredicate(MPMediaPropertyPredicate(
            value: NSNumber(value: id),
            forProperty: MPMediaPlaylistPropertyPersistentID))
        return query.collections?.first
    }

    private func refreshNowPlaying() {
        guard state == .connected else { return }
        isPlaying = player.playbackState == .playing
        guard let item = player.nowPlayingItem else {
            nowPlaying = nil
            return
        }
        nowPlaying = NowPlaying(
            title: item.title ?? "Unknown track",
            artist: item.artist ?? item.albumArtist ?? "",
            artwork: item.artwork?.image(at: CGSize(width: 120, height: 120)))
    }

    // MARK: - Remembered selection

    private func select(_ playlist: PlaylistRef) {
        selectedPlaylist = playlist
        UserDefaults.standard.set(String(playlist.id), forKey: "musicPlaylistID")
        UserDefaults.standard.set(playlist.name, forKey: "musicPlaylistName")
    }

    func clearSelection() {
        selectedPlaylist = nil
        UserDefaults.standard.removeObject(forKey: "musicPlaylistID")
        UserDefaults.standard.removeObject(forKey: "musicPlaylistName")
    }

    /// Persisted as a string: a persistent ID is a `UInt64` and doesn't survive
    /// `UserDefaults`' integer storage intact.
    private func restoreSelection() {
        guard selectedPlaylist == nil,
              let raw = UserDefaults.standard.string(forKey: "musicPlaylistID"),
              let id = UInt64(raw)
        else { return }
        let name = UserDefaults.standard.string(forKey: "musicPlaylistName") ?? "Playlist"
        selectedPlaylist = PlaylistRef(id: id, name: name, count: 0)
    }
}
