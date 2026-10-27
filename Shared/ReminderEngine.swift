import Foundation

struct ReminderEngine {
    static let promptLifetime: TimeInterval = 5 * 60

    var settings: AppSettings
    private(set) var state: ReminderState

    init(settings: AppSettings, state: ReminderState = ReminderState()) {
        self.settings = settings
        self.state = state
    }

    /// Reconcile persisted state with the schedule and advance all deadlines up to `now`.
    /// Callers should only deliver events whose dates are still relevant to the user.
    @discardableResult
    mutating func advance(to now: Date, calendar: Calendar = .current) -> [ReminderEvent] {
        var events: [ReminderEvent] = []
        let current = Schedule.activeWindow(at: now, plans: settings.plans, calendar: calendar)

        if state.window != current {
            if let old = state.window, old.end <= now {
                events.append(ReminderEvent(kind: .windowEnded, date: old.end))
            }
            state = ReminderState()
            if let current {
                state.window = current
                state.phase = .working(due: current.start.addingTimeInterval(20 * 60))
                events.append(ReminderEvent(kind: .windowStarted, date: current.start))
            }
        }

        guard let window = state.window else { return events }
        // Every transition advances the deadline by at least one minute. The cap protects
        // against corrupted persisted state without affecting a normal daily window.
        for _ in 0..<1500 {
            let deadline: Date
            switch state.phase {
            case .inactive: return events
            case .working(let due), .waitingForRetry(let due), .snoozed(let due): deadline = due
            case .prompted(let due, _): deadline = due.addingTimeInterval(Self.promptLifetime)
            case .breaking(let end): deadline = end
            }
            guard deadline <= now, deadline < window.end else { break }

            switch state.phase {
            case .working(let due), .waitingForRetry(let due), .snoozed(let due):
                let retry = { if case .waitingForRetry = state.phase { return 1 }; return 0 }()
                state.phase = .prompted(due: due, retry: retry)
                events.append(ReminderEvent(kind: .reminder, date: due))
            case .prompted(let due, let retry):
                let expiration = due.addingTimeInterval(Self.promptLifetime)
                events.append(ReminderEvent(kind: .promptExpired, date: expiration))
                if retry == 0 {
                    state.phase = .waitingForRetry(due: expiration)
                } else {
                    state.phase = .working(due: expiration.addingTimeInterval(20 * 60))
                }
            case .breaking(let end):
                state.phase = .working(due: end.addingTimeInterval(20 * 60))
                events.append(ReminderEvent(kind: .breakEnded, date: end))
            case .inactive: return events
            }
        }
        return events
    }

    /// `forPromptDue` rejects actions arriving from a stale notification.
    @discardableResult
    mutating func startBreak(at now: Date, forPromptDue: Date? = nil, calendar: Calendar = .current) -> Bool {
        advance(to: now, calendar: calendar)
        guard case .prompted(let due, _) = state.phase,
              state.window?.contains(now) == true,
              now < due.addingTimeInterval(Self.promptLifetime),
              forPromptDue == nil || forPromptDue == due else { return false }
        state.phase = .breaking(end: now.addingTimeInterval(20))
        return true
    }

    @discardableResult
    mutating func snooze(at now: Date, forPromptDue: Date? = nil, calendar: Calendar = .current) -> Bool {
        advance(to: now, calendar: calendar)
        guard case .prompted(let due, _) = state.phase,
              state.window?.contains(now) == true,
              now < due.addingTimeInterval(Self.promptLifetime),
              forPromptDue == nil || forPromptDue == due else { return false }
        state.phase = .snoozed(due: now.addingTimeInterval(TimeInterval(settings.snoozeMinutes * 60)))
        return true
    }

    /// Forecast notification dates, assuming future prompts are ignored. Recompute this
    /// list whenever an action, settings change, timezone change, or launch occurs.
    func projectedEvents(from now: Date, through horizon: Date, calendar: Calendar = .current) -> [ReminderEvent] {
        guard horizon > now else { return [] }
        var copy = self
        copy.advance(to: now, calendar: calendar)
        var cursor = now
        var events: [ReminderEvent] = []
        for _ in 0..<500 {
            let next: Date?
            if let window = copy.state.window {
                let deadline: Date
                switch copy.state.phase {
                case .inactive: deadline = window.end
                case .working(let due), .waitingForRetry(let due), .snoozed(let due): deadline = due
                case .prompted(let due, _): deadline = due.addingTimeInterval(Self.promptLifetime)
                case .breaking(let end): deadline = end
                }
                next = min(deadline, window.end)
            } else {
                next = Schedule.nextWindow(after: cursor, plans: settings.plans, calendar: calendar)?.start
            }
            guard let next, next > cursor, next <= horizon else { break }
            events.append(contentsOf: copy.advance(to: next, calendar: calendar).filter { $0.date > now })
            cursor = next
        }
        return events
    }
}
