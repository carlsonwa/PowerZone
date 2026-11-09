import EventKit
import EventKitUI
import SwiftUI
import VisionKit

/// Apple's own "New Event" sheet, pre-filled. Since iOS 17 this sheet runs outside the
/// app, so Kinboard needs no calendar permission: the person picks the calendar (a shared
/// iCloud family calendar, say) and taps Add.
struct AppleCalendarEditor: UIViewControllerRepresentable {
    let event: FamilyEvent
    let occurrence: EventOccurrence
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let ekEvent = EKEvent(eventStore: store)
        ekEvent.title = event.title
        ekEvent.isAllDay = event.isAllDay
        ekEvent.startDate = occurrence.start
        // EventKit's all-day end is the last day itself, not the midnight after it.
        ekEvent.endDate = event.isAllDay ? occurrence.end.addingTimeInterval(-1) : occurrence.end
        ekEvent.location = event.location.isEmpty ? nil : event.location
        ekEvent.notes = event.notes.isEmpty ? nil : event.notes
        if let rule = event.repeatRule {
            ekEvent.addRecurrenceRule(Self.recurrence(rule))
        }
        if event.reminder != .none, !event.isAllDay {
            ekEvent.addAlarm(EKAlarm(relativeOffset: -Double(event.reminder.rawValue) * 60))
        }

        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = ekEvent
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }

        func eventEditViewController(_ controller: EKEventEditViewController,
                                     didCompleteWith action: EKEventEditViewAction) {
            onDone()
        }
    }

    static func recurrence(_ rule: RepeatRule) -> EKRecurrenceRule {
        let frequency: EKRecurrenceFrequency
        switch rule.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        }
        let days: [EKRecurrenceDayOfWeek]? = rule.frequency == .weekly && !rule.weekdays.isEmpty
            ? rule.weekdays.compactMap { EKWeekday(rawValue: $0).map { EKRecurrenceDayOfWeek($0) } }
            : nil
        let end = rule.until.map { EKRecurrenceEnd(end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: $0))!.addingTimeInterval(-1)) }
        return EKRecurrenceRule(recurrenceWith: frequency, interval: max(1, rule.interval),
                                daysOfTheWeek: days, daysOfTheMonth: nil, monthsOfTheYear: nil,
                                weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: end)
    }
}

/// The system document scanner: finds the page edges, flattens and crops each page.
struct DocumentScanner: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void
    let onCancel: () -> Void

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan, onCancel: onCancel) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScan: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onScan: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            onScan((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            onCancel()
        }
    }
}
