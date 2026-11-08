import Foundation

struct AppSettings: Codable, Equatable {
    static let defaultSnoozeMinutes = 60
    static let snoozeChoices: Set<Int> = [15, 30, 60, 120]
    static let defaultWorkIntervalMinutes = 20
    static let defaultBreakDurationSeconds = 20
    static let workIntervalRange = 1...180
    static let breakDurationRange = 1...300

    var plans: [SchedulePlan]
    var snoozeMinutes: Int
    var workIntervalMinutes: Int
    var breakDurationSeconds: Int

    init(plans: [SchedulePlan] = [], snoozeMinutes: Int = defaultSnoozeMinutes,
         workIntervalMinutes: Int = defaultWorkIntervalMinutes,
         breakDurationSeconds: Int = defaultBreakDurationSeconds) {
        self.plans = plans
        self.snoozeMinutes = snoozeMinutes
        self.workIntervalMinutes = workIntervalMinutes
        self.breakDurationSeconds = breakDurationSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case plans, snoozeMinutes, workIntervalMinutes, breakDurationSeconds
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        plans = try values.decode([SchedulePlan].self, forKey: .plans)
        snoozeMinutes = try values.decode(Int.self, forKey: .snoozeMinutes)
        workIntervalMinutes = try values.decodeIfPresent(Int.self, forKey: .workIntervalMinutes) ?? Self.defaultWorkIntervalMinutes
        breakDurationSeconds = try values.decodeIfPresent(Int.self, forKey: .breakDurationSeconds) ?? Self.defaultBreakDurationSeconds
    }

    func validationErrors(calendar: Calendar = .current) -> [ScheduleValidationError] {
        var errors = Schedule.validationErrors(for: plans, calendar: calendar)
        if !Self.snoozeChoices.contains(snoozeMinutes) { errors.append(.invalidSnoozeDuration) }
        if !Self.workIntervalRange.contains(workIntervalMinutes) { errors.append(.invalidWorkInterval) }
        if !Self.breakDurationRange.contains(breakDurationSeconds) { errors.append(.invalidBreakDuration) }
        return errors
    }
}

enum SettingsStore {
    private static let key = "promodoro20.settings"
    private static let currentVersion = 1

    private struct Envelope: Codable {
        let version: Int
        let settings: AppSettings
    }

    enum StoreError: Error {
        case invalidSettings([ScheduleValidationError])
    }

    static func load(from defaults: UserDefaults = .standard) -> AppSettings? {
        guard let data = defaults.data(forKey: key),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == currentVersion,
              envelope.settings.validationErrors().isEmpty else { return nil }
        return envelope.settings
    }

    static func save(_ settings: AppSettings, to defaults: UserDefaults = .standard) throws {
        let errors = settings.validationErrors()
        guard errors.isEmpty else { throw StoreError.invalidSettings(errors) }
        let data = try JSONEncoder().encode(Envelope(version: currentVersion, settings: settings))
        defaults.set(data, forKey: key)
    }
}
