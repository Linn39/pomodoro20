import Foundation

enum ReminderPhase: Codable, Equatable {
    case inactive
    case working(due: Date)
    case prompted(due: Date, retry: Int)
    case waitingForRetry(due: Date)
    case breaking(end: Date)
    case snoozed(due: Date)
}

struct ReminderState: Codable, Equatable {
    var phase: ReminderPhase = .inactive
    var window: ScheduleWindow? = nil

    init(phase: ReminderPhase = .inactive, window: ScheduleWindow? = nil) {
        self.phase = phase
        self.window = window
    }
}

struct ReminderEvent: Equatable {
    enum Kind: Equatable {
        case windowStarted
        case windowEnded
        case reminder
        case promptExpired
        case breakEnded
    }

    let kind: Kind
    let date: Date

    /// For a reminder this is its scheduled timestamp and can identify the notification action.
    var promptDue: Date? { kind == .reminder ? date : nil }
}
