import Foundation

struct AppSettings: Codable, Equatable {
    static let defaultSnoozeMinutes = 60
    static let snoozeChoices: Set<Int> = [15, 30, 60, 120]

    var plans: [SchedulePlan]
    var snoozeMinutes: Int

    init(plans: [SchedulePlan] = [], snoozeMinutes: Int = defaultSnoozeMinutes) {
        self.plans = plans
        self.snoozeMinutes = snoozeMinutes
    }

    func validationErrors(calendar: Calendar = .current) -> [ScheduleValidationError] {
        var errors = Schedule.validationErrors(for: plans, calendar: calendar)
        if !Self.snoozeChoices.contains(snoozeMinutes) { errors.append(.invalidSnoozeDuration) }
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
