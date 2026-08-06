import SwiftUI

@main
struct PowerZoneRideApp: App {
    @StateObject private var meter = PowerMeterService()
    @StateObject private var client = HFBClient()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                LibraryView(client: client, meter: meter)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            NavigationLink {
                                SettingsView(meter: meter)
                            } label: {
                                Label("Settings", systemImage: "gearshape")
                            }
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
    }
}
