import XCTest
@testable import promodoro20

final class ScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return result
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testOvernightWindowBelongsToStartingWeekday() {
        let plan = SchedulePlan(weekdays: [2], startMinutes: 22 * 60, endMinutes: 2 * 60)
        let monday = date(2026, 10, 26, 22)
        let tuesday = date(2026, 10, 27, 1)
        let window = Schedule.activeWindow(at: tuesday, plans: [plan], calendar: calendar)
        XCTAssertEqual(window?.start, monday)
        XCTAssertEqual(window?.end, date(2026, 10, 27, 2))
        XCTAssertNil(Schedule.activeWindow(at: date(2026, 10, 27, 2), plans: [plan], calendar: calendar))
    }

    func testOvernightOverlapWithNextDayIsRejected() {
        let monday = SchedulePlan(weekdays: [2], startMinutes: 22 * 60, endMinutes: 2 * 60)
        let tuesday = SchedulePlan(weekdays: [3], startMinutes: 60, endMinutes: 3 * 60)
        let errors = Schedule.validationErrors(for: [monday, tuesday], calendar: calendar)
        XCTAssertTrue(errors.contains(.overlappingPlans(monday.id, tuesday.id)))
    }

    func testAdjacentWindowsAreAllowedAndDisabledPlanDoesNotOverlap() {
        let first = SchedulePlan(weekdays: [2], startMinutes: 9 * 60, endMinutes: 12 * 60)
        let adjacent = SchedulePlan(weekdays: [2], startMinutes: 12 * 60, endMinutes: 13 * 60)
        let disabled = SchedulePlan(weekdays: [2], startMinutes: 10 * 60, endMinutes: 11 * 60, isEnabled: false)
        XCTAssertTrue(Schedule.validationErrors(for: [first, adjacent, disabled], calendar: calendar).isEmpty)
    }

    func testNextWindowUsesCurrentTimeZoneAndDST() {
        let sunday = SchedulePlan(weekdays: [1], startMinutes: 2 * 60 + 30, endMinutes: 4 * 60)
        let beforeTransition = date(2026, 3, 28, 23)
        let next = Schedule.nextWindow(after: beforeTransition, plans: [sunday], calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: next!.start), 29)
        XCTAssertEqual(calendar.component(.hour, from: next!.start), 3)
        XCTAssertEqual(calendar.component(.hour, from: next!.end), 4)
    }

    func testNoWeekdaysAndEqualTimesAreInvalid() {
        let plan = SchedulePlan(weekdays: [], startMinutes: 600, endMinutes: 600)
        let errors = Schedule.validationErrors(for: [plan], calendar: calendar)
        XCTAssertTrue(errors.contains(.noWeekdays(plan.id)))
        XCTAssertTrue(errors.contains(.invalidTime(plan.id)))
    }
}
