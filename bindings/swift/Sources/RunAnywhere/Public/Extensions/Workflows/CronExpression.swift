//
//  CronExpression.swift
//  RunAnywhere
//
//  Five-field cron, parsed and evaluated in Swift.
//

import Foundation

/// A `minute hour day-of-month month day-of-week` expression.
///
/// Ported from `core/src/agent/cron.cpp`. Workflows are moving out of commons
/// and into this layer, so every binding that wants them re-implements against
/// its own runtime rather than against a shared C ABI. This is the first piece
/// across because it is pure calendar arithmetic with no dependency on the
/// workflow types.
///
/// Each field takes `*`, a number, a comma-separated list, an `a-b` range, and
/// a `/step` on any of those. Day-of-week takes 0 or 7 for Sunday. The
/// `@hourly`, `@daily`, `@midnight`, `@weekly`, `@monthly`, `@yearly` and
/// `@annually` aliases stand in for all five fields. Month and day *names*
/// (`JAN`, `MON`), `@reboot`, and the non-standard seconds and year fields are
/// refused, matching what the C++ accepted — an expression that parsed there
/// and not here would be a schedule that silently stopped firing.
///
/// Cron describes wall-clock time, so the caller supplies the calendar and its
/// timezone. A firing inside a DST transition is computed against the offset
/// that calendar carries, not the one in force at the instant.
public struct CronExpression: Equatable {
    /// How far ahead `nextDate(after:)` looks before giving up. Four years, so
    /// a 29 February schedule is still found.
    public static let searchYears = 4

    private let minutes: Set<Int>
    private let hours: Set<Int>
    private let days: Set<Int>
    private let months: Set<Int>
    private let weekdays: Set<Int>
    private let dayRestricted: Bool
    private let weekdayRestricted: Bool

    public enum Failure: Error, Equatable {
        case fieldCount(Int)
        case unknownAlias(String)
        case malformed(field: String)
        case outOfRange(field: String)

        public var message: String {
            switch self {
            case .fieldCount(let count):
                "A cron expression has five fields; this one has \(count)."
            case .unknownAlias(let alias):
                "\(alias) is not one of the accepted shorthands."
            case .malformed(let field):
                "\(field) is not a value this field understands."
            case .outOfRange(let field):
                "\(field) is outside what this field allows."
            }
        }
    }

    private static let aliases: [String: String] = [
        "@hourly": "0 * * * *",
        "@daily": "0 0 * * *",
        "@midnight": "0 0 * * *",
        "@weekly": "0 0 * * 0",
        "@monthly": "0 0 1 * *",
        "@yearly": "0 0 1 1 *",
        "@annually": "0 0 1 1 *"
    ]

    public init(_ text: String) throws {
        var expression = text.trimmingCharacters(in: .whitespaces)
        if expression.hasPrefix("@") {
            guard let expanded = Self.aliases[expression.lowercased()] else {
                throw Failure.unknownAlias(expression)
            }
            expression = expanded
        }

        let fields = expression.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count == 5 else { throw Failure.fieldCount(fields.count) }

        minutes = try Self.field(fields[0], range: 0 ... 59)
        hours = try Self.field(fields[1], range: 0 ... 23)
        days = try Self.field(fields[2], range: 1 ... 31)
        months = try Self.field(fields[3], range: 1 ... 12)
        // Seven means Sunday, and so does zero. Folded here so matching does not
        // have to know there are two spellings.
        weekdays = Set(try Self.field(fields[4], range: 0 ... 7).map { $0 == 7 ? 0 : $0 })

        dayRestricted = fields[2] != "*"
        weekdayRestricted = fields[4] != "*"
    }

    /// Whether the fields can ever line up on a real date, so `0 0 30 2 *` is
    /// rejected as a schedule rather than silently never firing.
    public var everFires: Bool {
        guard dayRestricted else { return true }
        let lengths = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return months.contains { month in days.contains { $0 <= lengths[month - 1] } }
    }

    /// The first firing strictly after `date`, or nil when none falls within
    /// `searchYears`.
    public func nextDate(after date: Date, calendar: Calendar) -> Date? {
        guard everFires else { return nil }

        // Strictly after: start from the top of the next minute, so a schedule
        // that matches `date` exactly does not return `date` itself.
        let truncated = calendar.date(
            from: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        ) ?? date
        let start = calendar.date(byAdding: .minute, value: 1, to: truncated)
        guard var cursor = start else { return nil }
        guard let horizon = calendar.date(byAdding: .year, value: Self.searchYears, to: cursor) else {
            return nil
        }

        // Day by day, not minute by minute: four years of minutes is two
        // million steps, and all but a handful are rejected by the date fields.
        while cursor < horizon {
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: cursor)
            guard let month = parts.month, let day = parts.day,
                  let weekday = parts.weekday, let hour = parts.hour, let minute = parts.minute else {
                return nil
            }

            if matches(month: month, day: day, weekday: weekday - 1) {
                for candidateHour in hours.sorted() where candidateHour >= hour {
                    for candidateMinute in minutes.sorted()
                    where candidateHour > hour || candidateMinute >= minute {
                        var when = parts
                        when.hour = candidateHour
                        when.minute = candidateMinute
                        when.second = 0
                        when.weekday = nil
                        if let fire = calendar.date(from: when), fire < horizon {
                            return fire
                        }
                    }
                }
            }

            // Nothing left today, so move to midnight tomorrow rather than
            // walking the rest of the hours of a day already ruled out.
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: cursor),
                  let midnight = calendar.date(
                      from: calendar.dateComponents([.year, .month, .day], from: tomorrow)
                  ) else {
                return nil
            }
            cursor = midnight
        }
        return nil
    }

    /// Day-of-month and day-of-week are OR-ed when both are restricted, which is
    /// cron's oldest and least obvious rule: `0 0 13 * 5` is the thirteenth *or*
    /// any Friday, not Friday the thirteenth.
    private func matches(month: Int, day: Int, weekday: Int) -> Bool {
        guard months.contains(month) else { return false }
        let dayHit = days.contains(day)
        let weekdayHit = weekdays.contains(weekday)
        if dayRestricted && weekdayRestricted { return dayHit || weekdayHit }
        if dayRestricted { return dayHit }
        if weekdayRestricted { return weekdayHit }
        return true
    }

    /// One field, expanded to the values it names.
    private static func field(_ text: String, range: ClosedRange<Int>) throws -> Set<Int> {
        var values: Set<Int> = []
        for part in text.split(separator: ",", omittingEmptySubsequences: false) {
            let piece = String(part)
            guard !piece.isEmpty else { throw Failure.malformed(field: text) }

            let halves = piece.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard halves.count <= 2 else { throw Failure.malformed(field: text) }

            var step = 1
            if halves.count == 2 {
                guard let parsed = Int(halves[1]), parsed > 0 else {
                    throw Failure.malformed(field: text)
                }
                step = parsed
            }

            let span = try bounds(halves[0], range: range, field: text)
            for value in stride(from: span.lowerBound, through: span.upperBound, by: step) {
                values.insert(value)
            }
        }
        guard !values.isEmpty else { throw Failure.malformed(field: text) }
        return values
    }

    /// `*`, `n`, or `a-b`, as the span it covers.
    private static func bounds(
        _ text: String, range: ClosedRange<Int>, field: String
    ) throws -> ClosedRange<Int> {
        if text == "*" { return range }

        if let dash = text.firstIndex(of: "-") {
            let lower = String(text[text.startIndex ..< dash])
            let upper = String(text[text.index(after: dash)...])
            guard let low = Int(lower), let high = Int(upper) else {
                throw Failure.malformed(field: field)
            }
            guard range.contains(low), range.contains(high), low <= high else {
                throw Failure.outOfRange(field: field)
            }
            return low ... high
        }

        guard let value = Int(text) else { throw Failure.malformed(field: field) }
        guard range.contains(value) else { throw Failure.outOfRange(field: field) }
        return value ... value
    }
}
