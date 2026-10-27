import Foundation

/// Weekdays use Calendar's numbering (Sunday = 1, Saturday = 7).
struct SchedulePlan: Codable, Equatable, Identifiable {
    var id: UUID
    var weekdays: Set<Int>
    var startMinutes: Int
    var endMinutes: Int
    var isEnabled: Bool

    init(id: UUID = UUID(), weekdays: Set<Int>, startMinutes: Int, endMinutes: Int, isEnabled: Bool = true) {
        self.id = id
        self.weekdays = weekdays
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.isEnabled = isEnabled
    }
}

struct ScheduleWindow: Codable, Equatable {
    var planID: UUID
    var start: Date
    var end: Date

    func contains(_ date: Date) -> Bool { start <= date && date < end }
}

enum ScheduleValidationError: LocalizedError, Equatable {
    case noWeekdays(UUID)
    case invalidWeekday(UUID)
    case invalidTime(UUID)
    case duplicatePlanID(UUID)
    case overlappingPlans(UUID, UUID)
    case invalidSnoozeDuration

    var errorDescription: String? {
        switch self {
        case .noWeekdays: "Choose at least one day for each plan."
        case .invalidWeekday: "A plan contains an invalid weekday."
        case .invalidTime: "Choose different start and end times within the day."
        case .duplicatePlanID: "Two plans have the same identifier."
        case .overlappingPlans: "Enabled plans cannot have overlapping time windows."
        case .invalidSnoozeDuration: "Choose a snooze duration of 15, 30, 60, or 120 minutes."
        }
    }
}

enum Schedule {
    /// Returns the active half-open window. An overnight window belongs to its starting weekday.
    static func activeWindow(at date: Date, plans: [SchedulePlan], calendar: Calendar = .current) -> ScheduleWindow? {
        let today = calendar.startOfDay(for: date)
        for offset in [-1, 0] {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for plan in plans where plan.isEnabled && plan.weekdays.contains(calendar.component(.weekday, from: day)) {
                if let window = window(for: plan, startingOn: day, calendar: calendar), window.contains(date) {
                    return window
                }
            }
        }
        return nil
    }

    /// Returns the next opening strictly after `date`.
    static func nextWindow(after date: Date, plans: [SchedulePlan], calendar: Calendar = .current) -> ScheduleWindow? {
        let today = calendar.startOfDay(for: date)
        var result: ScheduleWindow?
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for plan in plans where plan.isEnabled && plan.weekdays.contains(calendar.component(.weekday, from: day)) {
                guard let window = window(for: plan, startingOn: day, calendar: calendar), window.start > date else { continue }
                if result == nil || window.start < result!.start { result = window }
            }
        }
        return result
    }

    static func validationErrors(for plans: [SchedulePlan], calendar: Calendar = .current) -> [ScheduleValidationError] {
        var errors: [ScheduleValidationError] = []
        var ids: Set<UUID> = []
        for plan in plans {
            if !ids.insert(plan.id).inserted { errors.append(.duplicatePlanID(plan.id)) }
            if plan.weekdays.isEmpty { errors.append(.noWeekdays(plan.id)) }
            if !plan.weekdays.isSubset(of: Set(1...7)) { errors.append(.invalidWeekday(plan.id)) }
            if !(0..<1440).contains(plan.startMinutes) || !(0..<1440).contains(plan.endMinutes) || plan.startMinutes == plan.endMinutes {
                errors.append(.invalidTime(plan.id))
            }
        }
        guard errors.isEmpty else { return errors }

        // Two weeks catches weekly wraparound and overnight windows on both sides of Sunday.
        let base = calendar.startOfDay(for: Date(timeIntervalSince1970: 0))
        var windows: [ScheduleWindow] = []
        for offset in -1...14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: base) else { continue }
            for plan in plans where plan.isEnabled && plan.weekdays.contains(calendar.component(.weekday, from: day)) {
                if let window = window(for: plan, startingOn: day, calendar: calendar) { windows.append(window) }
            }
        }
        windows.sort { $0.start < $1.start }
        for index in windows.indices.dropFirst() where windows[index].start < windows[index - 1].end {
            let earlier = windows[index - 1]
            let later = windows[index]
            let error = ScheduleValidationError.overlappingPlans(earlier.planID, later.planID)
            if !errors.contains(error) { errors.append(error) }
        }
        return errors
    }

    private static func window(for plan: SchedulePlan, startingOn day: Date, calendar: Calendar) -> ScheduleWindow? {
        guard (0..<1440).contains(plan.startMinutes), (0..<1440).contains(plan.endMinutes), plan.startMinutes != plan.endMinutes else { return nil }
        let overnight = plan.endMinutes < plan.startMinutes
        guard let endDay = calendar.date(byAdding: .day, value: overnight ? 1 : 0, to: day),
              let start = clockDate(minutes: plan.startMinutes, on: day, calendar: calendar),
              let end = clockDate(minutes: plan.endMinutes, on: endDay, calendar: calendar),
              end > start else { return nil }
        return ScheduleWindow(planID: plan.id, start: start, end: end)
    }

    private static func clockDate(minutes: Int, on day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0,
                      of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
    }
}
