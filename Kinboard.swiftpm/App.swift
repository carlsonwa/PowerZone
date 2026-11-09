import SwiftUI
import UserNotifications

@main
struct KinboardApp: App {
    @StateObject private var store = FamilyStore()
    @StateObject private var router = Router()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(router)
        }
    }
}

/// Which tab is showing, and the Inbox's navigation path — shared so the Today screen can
/// jump straight to a message it just captured.
@MainActor
final class Router: ObservableObject {
    enum Tab: Hashable { case today, calendar, tasks, inbox, spending }

    @Published var tab: Tab = .today
    @Published var inboxPath: [UUID] = []

    func openMessage(_ id: UUID) {
        tab = .inbox
        inboxPath = [id]
    }
}

/// Shows reminders as banners even while Kinboard is open.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
