import SwiftUI
import UserNotifications
import WatchKit

@main
struct promodoro20WatchApp: App {
    @StateObject private var controller = WatchReminderController.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Register the notification delegate before a background notification
        // action can be delivered, even if no interface has appeared yet.
        _ = WatchReminderController.shared
    }

    var body: some Scene {
        WindowGroup {
            ReminderView(controller: controller)
                .onAppear { controller.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { controller.refresh() }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)) { _ in
                    controller.refresh()
                }
        }
        .backgroundTask(.appRefresh("replenishReminders")) {
            await MainActor.run { controller.refresh() }
        }
    }
}

@MainActor
final class WatchReminderController: ObservableObject {
    static let shared = WatchReminderController()
    @Published private(set) var state = ReminderState()
    @Published private(set) var hasSettings = false
    @Published private(set) var snoozeMinutes = AppSettings.defaultSnoozeMinutes
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var now = Date()
    @Published private(set) var feedback: String?
    @Published private(set) var deliveryIssue: String?

    private static let stateKey = "promodoro20.reminderState"
    private let delivery = ReminderDelivery()
    private let sync = WatchSync()
    private var engine: ReminderEngine?
    private var started = false

    init() {
        if let settings = SettingsStore.load() {
            let savedState: ReminderState
            if let data = UserDefaults.standard.data(forKey: Self.stateKey),
               let decoded = try? JSONDecoder().decode(ReminderState.self, from: data) {
                savedState = decoded
            } else {
                savedState = ReminderState()
            }
            engine = ReminderEngine(settings: settings, state: savedState)
            state = savedState
            hasSettings = true
            snoozeMinutes = settings.snoozeMinutes
        }
        start()
    }

    func start() {
        guard !started else { return }
        started = true
        delivery.onAction = { [weak self] action, due, completion in
            DispatchQueue.main.async {
                self?.handle(action: action, promptDue: due)
                completion()
            }
        }
        delivery.onDelivered = { [weak self] in
            DispatchQueue.main.async { self?.refresh() }
        }
        delivery.onAuthorizationStatus = { [weak self] status in
            DispatchQueue.main.async {
                self?.authorizationStatus = status
                if status == .notDetermined && self?.hasSettings == true {
                    self?.delivery.requestAuthorization()
                }
            }
        }
        delivery.onSchedulingError = { [weak self] in
            DispatchQueue.main.async {
                self?.deliveryIssue = "Watch could not schedule an alert. Open the app to retry."
            }
        }
        delivery.configure(snoozeMinutes: snoozeMinutes)
        sync.onSettings = { [weak self] settings in self?.receive(settings: settings) }
        sync.activate()
        refresh()
    }

    func refresh() {
        let date = Date()
        now = date
        delivery.refreshAuthorizationStatus()
        guard var engine else {
            delivery.schedule(events: [], settings: nil, after: date)
            return
        }
        let events = engine.advance(to: date)
        self.engine = engine
        state = engine.state
        saveState()

        if events.contains(where: { $0.kind == .breakEnded && date.timeIntervalSince($0.date) < 2 }) {
            WKInterfaceDevice.current().play(.success)
        }
        scheduleProjectedEvents(after: date)
    }

    func tick() {
        let date = Date()
        now = date
        guard let deadline = nextDeadline, deadline <= date else { return }
        refresh()
    }

    func startBreak() { handle(action: .startBreak, promptDue: nil) }
    func snooze() { handle(action: .snooze, promptDue: nil) }

    var nextDeadline: Date? {
        switch state.phase {
        case .inactive: return nil
        case .working(let due), .waitingForRetry(let due), .snoozed(let due): return min(due, state.window?.end ?? due)
        case .prompted(let due, _): return min(due.addingTimeInterval(60), state.window?.end ?? due)
        case .breaking(let end): return min(end, state.window?.end ?? end)
        }
    }

    var nextOpening: Date? {
        guard let engine else { return nil }
        return Schedule.nextWindow(after: now, plans: engine.settings.plans)?.start
    }

    private func handle(action: WatchReminderAction, promptDue: Date?) {
        guard var engine else { return }
        let date = Date()
        _ = engine.advance(to: date)
        let accepted: Bool
        switch action {
        case .startBreak: accepted = engine.startBreak(at: date, forPromptDue: promptDue)
        case .snooze: accepted = engine.snooze(at: date, forPromptDue: promptDue)
        }
        feedback = accepted ? nil : "That reminder has expired."
        self.engine = engine
        state = engine.state
        now = date
        saveState()
        scheduleProjectedEvents(after: date)
    }

    private func receive(settings: AppSettings) {
        guard settings.validationErrors().isEmpty else { return }
        do { try SettingsStore.save(settings) } catch { return }
        engine = ReminderEngine(settings: settings, state: engine?.state ?? ReminderState())
        hasSettings = true
        snoozeMinutes = settings.snoozeMinutes
        delivery.configure(snoozeMinutes: settings.snoozeMinutes)
        refresh()
    }

    private func saveState() {
        guard let engine, let data = try? JSONEncoder().encode(engine.state) else { return }
        UserDefaults.standard.set(data, forKey: Self.stateKey)
    }

    private func scheduleProjectedEvents(after date: Date) {
        guard let engine else { return }
        deliveryIssue = nil
        let horizon = date.addingTimeInterval(7 * 24 * 60 * 60)
        let events = engine.projectedEvents(from: date, through: horizon)
        let lastQueued = delivery.schedule(events: events, settings: engine.settings, after: date)
        let refreshDelay: TimeInterval
        if let lastQueued {
            let halfCoverage = lastQueued.timeIntervalSince(date) / 2
            refreshDelay = min(6 * 60 * 60, max(15 * 60, halfCoverage))
        } else {
            refreshDelay = 6 * 60 * 60
        }
        // Opportunistically replenish the finite notification queue. watchOS may defer this task.
        WKExtension.shared().scheduleBackgroundRefresh(
            withPreferredDate: date.addingTimeInterval(refreshDelay),
            userInfo: "replenishReminders" as NSString) { [weak self] error in
                if error != nil {
                    DispatchQueue.main.async {
                        self?.deliveryIssue = "Automatic schedule refresh is unavailable. Open the app periodically."
                    }
                }
            }
    }
}
