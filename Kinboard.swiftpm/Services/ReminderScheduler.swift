import Foundation
import UserNotifications

/// Keeps the phone's scheduled notifications in step with the family's data. iOS allows
/// 64 pending notifications per app, so rather than tracking each one, every save clears
/// Kinboard's and schedules the next two weeks again, soonest first.
enum ReminderScheduler {
    static let horizonDays = 14
    static let maxPending = 60

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Asks for notification permission the first time something gets a reminder.
    @discardableResult
    static func requestPermissionIfNeeded(_ needed: Bool) async -> Bool {
        guard needed else { return false }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .notDetermined { return await requestPermission() }
        return await isAuthorized()
    }

    static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    static func reschedule(_ data: FamilyData, calendar: Calendar = .current, now: Date = Date()) async {
        guard await isAuthorized() else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for request in requests(for: data, calendar: calendar, now: now) {
            try? await center.add(request)
        }
    }

    static func requests(for data: FamilyData, calendar: Calendar, now: Date) -> [UNNotificationRequest] {
        guard let horizon = calendar.date(byAdding: .day, value: horizonDays, to: now) else { return [] }
        var pending: [(Date, String, UNMutableNotificationContent)] = []

        let timeFormat = Date.FormatStyle(date: .omitted, time: .shortened)
        let dayFormat = Date.FormatStyle().weekday(.wide).month(.abbreviated).day()

        for event in data.events where event.reminder != .none {
            // Look a week past the horizon so a "1 week before" reminder is still found.
            let lookAhead = calendar.date(byAdding: .day, value: 7, to: horizon) ?? horizon
            for occurrence in event.occurrences(from: now, to: lookAhead, calendar: calendar) {
                guard let fire = ReminderSchedule.fireDate(occurrenceStart: occurrence.start, isAllDay: event.isAllDay,
                                                           offset: event.reminder, calendar: calendar),
                      fire > now, fire < horizon else { continue }
                let content = UNMutableNotificationContent()
                content.title = event.title
                var when = calendar.isDate(occurrence.start, inSameDayAs: fire)
                    ? (event.isAllDay ? "Today" : "Today at " + occurrence.start.formatted(timeFormat))
                    : occurrence.start.formatted(dayFormat) + (event.isAllDay ? "" : " at " + occurrence.start.formatted(timeFormat))
                if !event.location.isEmpty { when += " · " + event.location }
                content.body = when
                content.sound = .default
                pending.append((fire, "event.\(event.id.uuidString).\(Int(occurrence.start.timeIntervalSince1970))", content))
            }
        }

        for task in data.tasks {
            guard let fire = ReminderSchedule.fireDate(for: task, calendar: calendar), fire > now, fire < horizon else { continue }
            let content = UNMutableNotificationContent()
            content.title = task.title
            content.body = task.hasDueTime ? "Due now" : "Due today"
            if let assignee = data.member(task.assigneeID) { content.body += " · " + assignee.firstName }
            content.sound = .default
            pending.append((fire, "task.\(task.id.uuidString)", content))
        }

        return pending.sorted { $0.0 < $1.0 }.prefix(maxPending).map { fire, id, content in
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            return UNNotificationRequest(identifier: "kinboard.\(id)", content: content, trigger: trigger)
        }
    }
}
