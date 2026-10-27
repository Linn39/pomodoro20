import XCTest
@testable import promodoro20

final class ReminderEngineTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    private func date(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: hour, minute: minute, second: second))!
    }

    private func engine(endMinutes: Int = 12 * 60, snoozeMinutes: Int = 60) -> ReminderEngine {
        let plan = SchedulePlan(weekdays: [2], startMinutes: 9 * 60, endMinutes: endMinutes)
        return ReminderEngine(settings: AppSettings(plans: [plan], snoozeMinutes: snoozeMinutes))
    }

    func testIgnoredPromptRetriesThenRestartsTwentyMinuteCycle() {
        var subject = engine()
        let events = subject.advance(to: date(9, 30), calendar: calendar)
        XCTAssertEqual(events.filter { $0.kind == .reminder }.map(\.date), [date(9, 20), date(9, 25)])
        XCTAssertEqual(events.filter { $0.kind == .promptExpired }.map(\.date), [date(9, 25), date(9, 30)])
        XCTAssertEqual(subject.state.phase, .working(due: date(9, 50)))
    }

    func testRetryStartsWhenFirstReminderExpiresAndOldActionIsRejected() {
        var subject = engine()
        let projected = subject.projectedEvents(from: date(9, 19, 59), through: date(9, 25), calendar: calendar)
        XCTAssertEqual(projected.filter { $0.kind == .reminder }.map(\.date), [date(9, 20), date(9, 25)])

        subject.advance(to: date(9, 24, 59), calendar: calendar)
        XCTAssertEqual(subject.state.phase, .prompted(due: date(9, 20), retry: 0))

        let events = subject.advance(to: date(9, 25), calendar: calendar)
        XCTAssertEqual(events, [ReminderEvent(kind: .promptExpired, date: date(9, 25)),
                                ReminderEvent(kind: .reminder, date: date(9, 25))])
        XCTAssertEqual(subject.state.phase, .prompted(due: date(9, 25), retry: 1))
        XCTAssertFalse(subject.startBreak(at: date(9, 25), forPromptDue: date(9, 20), calendar: calendar))
        XCTAssertTrue(subject.startBreak(at: date(9, 25), forPromptDue: date(9, 25), calendar: calendar))
    }

    func testSnoozeUsesTapTimeAndRejectsExpiredAction() {
        var subject = engine(snoozeMinutes: 30)
        subject.advance(to: date(9, 20), calendar: calendar)
        XCTAssertTrue(subject.snooze(at: date(9, 20, 30), forPromptDue: date(9, 20), calendar: calendar))
        XCTAssertEqual(subject.state.phase, .snoozed(due: date(9, 50, 30)))
        XCTAssertFalse(subject.startBreak(at: date(9, 25), forPromptDue: date(9, 20), calendar: calendar))
        subject.advance(to: date(9, 50, 30), calendar: calendar)
        XCTAssertEqual(subject.state.phase, .prompted(due: date(9, 50, 30), retry: 0))
    }

    func testBreakCutOffByWindowEnd() {
        var subject = engine(endMinutes: 9 * 60 + 21)
        subject.advance(to: date(9, 20, 50), calendar: calendar)
        XCTAssertTrue(subject.startBreak(at: date(9, 20, 50), calendar: calendar))
        let events = subject.advance(to: date(9, 21), calendar: calendar)
        XCTAssertEqual(events.filter { $0.kind == .windowEnded }.map(\.date), [date(9, 21)])
        XCTAssertFalse(events.contains { $0.kind == .breakEnded })
        XCTAssertEqual(subject.state.phase, .inactive)
    }

    func testBreakCompletionStartsNextWorkInterval() {
        var subject = engine()
        subject.advance(to: date(9, 20), calendar: calendar)
        XCTAssertTrue(subject.startBreak(at: date(9, 20, 10), calendar: calendar))
        let events = subject.advance(to: date(9, 20, 30), calendar: calendar)
        XCTAssertTrue(events.contains(ReminderEvent(kind: .breakEnded, date: date(9, 20, 30))))
        XCTAssertEqual(subject.state.phase, .working(due: date(9, 40, 30)))
    }

    func testProjectedEventsIncludeWindowBoundariesAndNoExpiredBreakAlert() {
        var subject = engine(endMinutes: 9 * 60 + 21)
        subject.advance(to: date(9, 20, 50), calendar: calendar)
        XCTAssertTrue(subject.startBreak(at: date(9, 20, 50), calendar: calendar))
        let events = subject.projectedEvents(from: date(9, 20, 50), through: date(9, 22), calendar: calendar)
        XCTAssertEqual(events.map(\.kind), [.windowEnded])
    }
}
