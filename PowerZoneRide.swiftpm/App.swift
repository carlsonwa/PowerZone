import SwiftUI

@main
struct PowerZoneRideApp: App {
    @StateObject private var meter = PowerMeterService()
    @StateObject private var client = HFBClient()
    @StateObject private var music = AppleMusicService()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                LibraryView(client: client, meter: meter, music: music)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            NavigationLink {
                                SettingsView(meter: meter, music: music)
                            } label: {
                                Label("Settings", systemImage: "gearshape")
                            }
                        }
                    }
            }
            .preferredColorScheme(.dark)
            // Picks up an access grant from a previous launch, so a returning rider is
            // connected before they open Settings.
            .task { music.start() }
        }
    }
}
