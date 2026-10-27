import Foundation
import UserNotifications
import WatchKit

/// Local notifications are scheduled by the watch, using absolute dates projected by the engine.
final class ReminderDelivery: NSObject, UNUserNotificationCenterDelegate {
    private enum Identifier {
        static let prefix = "promodoro20."
        static let reminderCategory = "breakReminder"
        static let startBreak = "startBreak"
        static let snooze = "snooze"
        static let promptDue = "promptDue"
        static let kind = "kind"
        static let breakEndDate = "breakEndDate"
    }

    var onAction: ((WatchReminderAction, Date, @escaping () -> Void) -> Void)?
    var onDelivered: (() -> Void)?
    var onForegroundBreakEnded: ((Date) -> Void)?
    var onAuthorizationStatus: ((UNAuthorizationStatus) -> Void)?
    var onSchedulingError: (() -> Void)?
    private var scheduleRevision = 0

    func configure(snoozeMinutes: Int) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let start = UNNotificationAction(identifier: Identifier.startBreak, title: "Start Break", options: [])
        let snooze = UNNotificationAction(identifier: Identifier.snooze,
                                            title: "Snooze \(snoozeMinutes) min", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Identifier.reminderCategory,
                                   actions: [start, snooze], intentIdentifiers: [], options: [])
        ])
        refreshAuthorizationStatus()
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            self?.refreshAuthorizationStatus()
        }
    }

    func refreshAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            self?.onAuthorizationStatus?(settings.authorizationStatus)
        }
    }

    @discardableResult
    func schedule(events: [ReminderEvent], settings: AppSettings?, after now: Date,
                  activeReminderDue: Date? = nil) -> Date? {
        scheduleRevision += 1
        let revision = scheduleRevision
        let boundaries = settings.map(boundaryRequests(for:)) ?? []
        let transient = Array(events.filter {
            $0.date > now && ($0.kind == .reminder || $0.kind == .breakEnded)
        }.prefix(max(0, 60 - boundaries.count)))
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { [weak self] notifications in
            DispatchQueue.main.async {
                guard let self, self.scheduleRevision == revision else { return }
                let obsolete = notifications.filter { notification in
                    let request = notification.request
                    guard request.identifier.hasPrefix(Identifier.prefix),
                          request.content.categoryIdentifier == Identifier.reminderCategory else { return false }
                    guard let due = request.content.userInfo[Identifier.promptDue] as? TimeInterval else { return true }
                    return due + ReminderEngine.promptLifetime <= Date().timeIntervalSince1970
                        || due != activeReminderDue?.timeIntervalSince1970
                }.map { $0.request.identifier }
                center.removeDeliveredNotifications(withIdentifiers: obsolete)
            }
        }
        center.getPendingNotificationRequests { [weak self] requests in
            DispatchQueue.main.async {
                guard let self, self.scheduleRevision == revision else { return }
                let owned = requests.map(\.identifier).filter { $0.hasPrefix(Identifier.prefix) }
                center.removePendingNotificationRequests(withIdentifiers: owned)

                // Calendar triggers repeat weekly, so window boundaries remain covered
                // even when watchOS delays a background refresh.
                for request in boundaries.prefix(60) { self.add(request, to: center) }
                for (index, event) in transient.enumerated() {
                    let content = self.content(for: event)
                    let trigger = UNTimeIntervalNotificationTrigger(
                        timeInterval: max(1, event.date.timeIntervalSinceNow), repeats: false)
                    let request = UNNotificationRequest(identifier: "\(Identifier.prefix)\(index)",
                                                        content: content, trigger: trigger)
                    self.add(request, to: center)
                }
            }
        }
        return transient.last?.date
    }

    private func add(_ request: UNNotificationRequest, to center: UNUserNotificationCenter) {
        center.add(request) { [weak self] error in
            if error != nil { self?.onSchedulingError?() }
        }
    }

    private func boundaryRequests(for settings: AppSettings) -> [UNNotificationRequest] {
        var requests: [UNNotificationRequest] = []
        for plan in settings.plans where plan.isEnabled {
            for weekday in plan.weekdays.sorted() {
                let start = DateComponents(hour: plan.startMinutes / 60,
                                           minute: plan.startMinutes % 60,
                                           weekday: weekday)
                let endWeekday = plan.endMinutes < plan.startMinutes ? weekday % 7 + 1 : weekday
                let end = DateComponents(hour: plan.endMinutes / 60,
                                         minute: plan.endMinutes % 60,
                                         weekday: endWeekday)
                for (kind, components, label) in [
                    (ReminderEvent.Kind.windowStarted, start, "start"),
                    (ReminderEvent.Kind.windowEnded, end, "end")
                ] {
                    let content = content(for: ReminderEvent(kind: kind, date: Date()))
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                    let id = "\(Identifier.prefix)boundary.\(plan.id).\(weekday).\(label)"
                    requests.append(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
                }
            }
        }
        return requests
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        onDelivered?()
        if notification.request.content.userInfo[Identifier.kind] as? String == "breakEnded" {
            if WKApplication.shared().applicationState == .active,
               let timestamp = notification.request.content.userInfo[Identifier.breakEndDate] as? TimeInterval {
                onForegroundBreakEnded?(Date(timeIntervalSince1970: timestamp))
                completionHandler([])
            } else {
                completionHandler([.banner, .sound])
            }
        } else {
            completionHandler([.banner, .sound])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.content.categoryIdentifier == Identifier.reminderCategory {
            center.removeDeliveredNotifications(withIdentifiers: [response.notification.request.identifier])
        }
        guard let due = response.notification.request.content.userInfo[Identifier.promptDue] as? TimeInterval else {
            onDelivered?()
            completionHandler()
            return
        }
        switch response.actionIdentifier {
        case Identifier.startBreak:
            if let onAction { onAction(.startBreak, Date(timeIntervalSince1970: due), completionHandler) }
            else { completionHandler() }
        case Identifier.snooze:
            if let onAction { onAction(.snooze, Date(timeIntervalSince1970: due), completionHandler) }
            else { completionHandler() }
        default:
            onDelivered?()
            completionHandler()
        }
    }

    private func content(for event: ReminderEvent) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.sound = .default
        switch event.kind {
        case .windowStarted:
            content.title = "promodoro20 is on"
            content.body = "Your next break reminder is in 20 minutes."
        case .windowEnded:
            content.title = "promodoro20 is off"
            content.body = "This plan's active window has ended."
        case .reminder:
            content.title = "Look into the distance"
            content.body = "Take a 20-second break."
            content.categoryIdentifier = Identifier.reminderCategory
            content.userInfo = [Identifier.promptDue: event.date.timeIntervalSince1970]
        case .breakEnded:
            content.title = "Break complete"
            content.body = "You can return to what you were doing."
            content.userInfo = [Identifier.kind: "breakEnded",
                                Identifier.breakEndDate: event.date.timeIntervalSince1970]
        case .promptExpired:
            break
        }
        return content
    }
}

enum WatchReminderAction {
    case startBreak
    case snooze
}
