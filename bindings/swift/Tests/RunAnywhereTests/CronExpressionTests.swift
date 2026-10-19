//
//  CronExpressionTests.swift
//  RunAnywhereTests
//
//  The cases from core/tests/test_cron.cpp, carried over with the code.
//

@testable import RunAnywhere
import XCTest

/// Ported alongside `CronExpression` so the Swift one is held to what the C++
/// one already promised. A schedule that fired under the old engine and not
/// under this one is a workflow that silently stops running, which nobody
/// notices until the thing it was supposed to do has not happened for a week.
final class CronExpressionTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var parts = DateComponents()
        parts.year = year; parts.month = month; parts.day = day
        parts.hour = hour; parts.minute = minute; parts.second = 0
        // The components are always a real date, so a failure here is a broken
        // test rather than a case worth handling.
        guard let date = calendar.date(from: parts) else {
            preconditionFailure("\(year)-\(month)-\(day) \(hour):\(minute) is not a date")
        }
        return date
    }

    private func next(_ expression: String, from: Date) throws -> Date? {
        try CronExpression(expression).nextDate(after: from, calendar: calendar)
    }

    // MARK: - Parsing

    func testTheAliasesExpand() throws {
        let midnight = date(2026, 3, 10, 12, 0)
        XCTAssertEqual(try next("@daily", from: midnight), date(2026, 3, 11, 0, 0))
        XCTAssertEqual(try next("@midnight", from: midnight), date(2026, 3, 11, 0, 0))
        XCTAssertEqual(try next("@hourly", from: midnight), date(2026, 3, 10, 13, 0))
        XCTAssertEqual(try next("@monthly", from: midnight), date(2026, 4, 1, 0, 0))
        XCTAssertEqual(try next("@yearly", from: midnight), date(2027, 1, 1, 0, 0))
        XCTAssertEqual(try next("@annually", from: midnight), date(2027, 1, 1, 0, 0))
    }

    func testMalformedExpressionsAreRefused() {
        // Each of these parsed nowhere in the C++ either. They are refused with
        // a reason rather than accepted and quietly never fired.
        for bad in [
            "* * * *",          // four fields
            "* * * * * *",      // six
            "@reboot",          // deliberately unsupported
            "@fortnightly",     // not an alias
            "0 0 * jan *",      // month names are not accepted
            "* * * * mon",      // nor day names
            "*/0 * * * *",      // a zero step
            "*/ * * * *",       // a step with nothing after it
            "*/1/2 * * * *",    // two steps
            "-5 * * * *",       // a range with no start
            "* 24 * * *",       // hour out of range
            "0 0 * 13 *",       // month out of range
            "0 0 * 0 *",        // month zero
            "0 0 * * 8"         // weekday out of range
        ] {
            XCTAssertThrowsError(try CronExpression(bad), "\(bad) should not parse")
        }
    }

    func testSundayIsBothZeroAndSeven() throws {
        let thursday = date(2026, 3, 12, 12, 0)
        let sunday = date(2026, 3, 15, 0, 0)
        XCTAssertEqual(try next("0 0 * * 0", from: thursday), sunday)
        XCTAssertEqual(try next("0 0 * * 7", from: thursday), sunday)
        XCTAssertEqual(try next("0 0 * * 0,7", from: thursday), sunday)
    }

    // MARK: - Firing

    func testEveryMinuteIsTheNextMinute() throws {
        XCTAssertEqual(try next("* * * * *", from: date(2026, 3, 10, 12, 30)),
                       date(2026, 3, 10, 12, 31))
    }

    func testStepsCountFromTheStartOfTheField() throws {
        XCTAssertEqual(try next("*/15 * * * *", from: date(2026, 3, 10, 12, 1)),
                       date(2026, 3, 10, 12, 15))
        XCTAssertEqual(try next("*/15 * * * *", from: date(2026, 3, 10, 12, 46)),
                       date(2026, 3, 10, 13, 0))
    }

    func testTheNextFiringIsStrictlyAfterTheInstantGiven() throws {
        // Exactly on a firing returns the following one, never the same instant,
        // or a scheduler that asks "what is next" while running would answer
        // "now" and run forever.
        XCTAssertEqual(try next("0 0 * * *", from: date(2026, 3, 10, 0, 0)),
                       date(2026, 3, 11, 0, 0))
    }

    func testDayOfMonthAndDayOfWeekAreOredWhenBothAreSet() throws {
        // Cron's oldest trap: `13 * 5` is the thirteenth OR any Friday, not
        // Friday the thirteenth. 2026-03-10 is a Tuesday; Friday is the 13th,
        // and the 13th is also the day-of-month, so the 11th must not match.
        let from = date(2026, 3, 10, 12, 0)
        XCTAssertEqual(try next("0 0 13 * 5", from: from), date(2026, 3, 13, 0, 0))
    }

    func testAScheduleThatCanNeverFireHasNoNextDate() throws {
        // 30 February. Accepted as an expression, but it never comes round.
        XCTAssertNil(try next("0 0 30 2 *", from: date(2026, 3, 10, 12, 0)))
    }

    func testTheTwentyNinthOfFebruaryIsFoundInALeapYear() throws {
        // The reason the search runs four years rather than one.
        XCTAssertEqual(try next("0 0 29 2 *", from: date(2026, 3, 1, 0, 0)),
                       date(2028, 2, 29, 0, 0))
    }

    func testARangeWithAStep() throws {
        XCTAssertEqual(try next("0 9-17/4 * * *", from: date(2026, 3, 10, 0, 0)),
                       date(2026, 3, 10, 9, 0))
        XCTAssertEqual(try next("0 9-17/4 * * *", from: date(2026, 3, 10, 9, 0)),
                       date(2026, 3, 10, 13, 0))
    }

    func testALeapDayScheduleIsNotReportedAsNeverFiring() throws {
        XCTAssertNoThrow(try CronExpression("0 0 29 2 *"))
        XCTAssertTrue(try CronExpression("0 0 29 2 *").everFires)
        XCTAssertFalse(try CronExpression("0 0 30 2 *").everFires)
    }
}
