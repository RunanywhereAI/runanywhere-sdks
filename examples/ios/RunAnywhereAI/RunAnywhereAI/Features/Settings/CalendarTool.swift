//
//  CalendarTool.swift
//  RunAnywhereAI
//
//  Calendar tool — lets the on-device assistant answer simple questions
//  about the user's own schedule ("what's on my calendar today", "am I
//  free this week"). Read-only, single tool, on purpose: this mirrors the
//  scope of get_current_time / get_weather rather than trying to be a full
//  calendar client.
//

import EventKit
import Foundation
import RunAnywhere

// MARK: - Calendar Manager

/// Read-only EventKit access for the `get_calendar_events` tool. Actor-isolated
/// for the same reason as HealthKitManager: EventKit's authorization callback
/// lands on a background queue. Unlike HealthKit, EventKit is a plain native
/// framework on both iOS and macOS, so this file needs no `#if os(iOS)` guard.
actor CalendarManager {
    static let shared = CalendarManager()

    private let store = EKEventStore()

    /// Requests full read/write access to Calendars. This tool only reads,
    /// but EventKit does not offer a read-only grant — write access is
    /// simply unused.
    func requestAuthorization() async throws {
        _ = try await store.requestFullAccessToEvents()
    }

    private struct CalendarDateRange {
        let start: Date
        let end: Date
        let label: String
    }

    private static let isoDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        return formatter
    }()

    static var todayString: String { isoDayFormatter.string(from: Date()) }

    private func parseISODay(_ string: String) -> Date? {
        CalendarManager.isoDayFormatter.date(from: string)
    }

    /// Same resolution strategy as HealthKitManager.resolveRange (explicit
    /// range wins, then keywords, then a single explicit day, then "today"),
    /// with calendar-appropriate keywords instead of health ones — a
    /// schedule question skews forward-looking ("this week", "tomorrow")
    /// rather than backward-looking.
    private func resolveRange(dateSpec: String?, startDate: String?, endDate: String?) -> CalendarDateRange {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        let effectiveStartDate = startDate ?? (endDate != nil ? dateSpec : nil)
        if let effectiveStartDate, let parsedStart = parseISODay(effectiveStartDate) {
            let startDay = calendar.startOfDay(for: parsedStart)
            let endDay: Date
            let label: String
            if let endDate, let parsedEnd = parseISODay(endDate), parsedEnd != parsedStart {
                endDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: parsedEnd)) ?? startDay
                label = "\(effectiveStartDate) to \(endDate)"
            } else {
                endDay = calendar.date(byAdding: .day, value: 1, to: startDay) ?? startDay
                label = effectiveStartDate
            }
            return CalendarDateRange(start: startDay, end: max(endDay, startDay), label: label)
        }

        switch dateSpec?.lowercased() {
        case "tomorrow":
            let start = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return CalendarDateRange(start: start, end: end, label: "tomorrow")
        case "this_week":
            let end = calendar.dateInterval(of: .weekOfYear, for: now)?.end ?? startOfToday
            return CalendarDateRange(start: startOfToday, end: max(end, startOfToday), label: "this_week")
        case "next_7_days":
            let end = calendar.date(byAdding: .day, value: 7, to: startOfToday) ?? startOfToday
            return CalendarDateRange(start: startOfToday, end: end, label: "next_7_days")
        case "today", .none:
            let end = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
            return CalendarDateRange(start: startOfToday, end: end, label: "today")
        case .some(let explicitDay):
            if let parsed = parseISODay(explicitDay) {
                let day = calendar.startOfDay(for: parsed)
                let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
                return CalendarDateRange(start: day, end: end, label: explicitDay)
            }
            let end = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
            return CalendarDateRange(start: startOfToday, end: end, label: "today")
        }
    }

    func fetchEvents(dateSpec: String?, startDate: String?, endDate: String?) async throws -> [String: RAToolValue] {
        let range = resolveRange(dateSpec: dateSpec, startDate: startDate, endDate: endDate)

        // EventKit caps predicateForEvents at a 4-year span; every range this
        // tool builds is well inside that, so no clamping needed here.
        let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: nil)
        let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        let summaries = events.map { event -> String in
            let timeText: String
            if event.isAllDay {
                timeText = "all day"
            } else {
                timeText = "\(timeFormatter.string(from: event.startDate)) - \(timeFormatter.string(from: event.endDate))"
            }
            let locationText = event.location.map { " at \($0)" } ?? ""
            return "\(event.title ?? "Untitled") (\(timeText)\(locationText))"
        }

        return [
            "event_count": RAToolValue(Double(events.count)),
            "events": RAToolValue(summaries.joined(separator: "; ")),
            "date": RAToolValue(range.label)
        ]
    }
}

// MARK: - get_calendar_events Tool

enum CalendarTool {
    static var definition: RAToolDefinition {
        let todayString = CalendarManager.todayString
        return RAToolDefinition(
            name: "get_calendar_events",
            description: """
                Gets the user's own Calendar events (meetings, appointments, plans) for a \
                specific day or date range. Use whenever the user asks about their schedule, \
                what's on their calendar, upcoming meetings, or free time (e.g. "what's on my \
                calendar today", "am I free this week", "do I have anything tomorrow"). Today's \
                date is \(todayString) — use that as your only source of truth for "today", \
                never guess or recall a date from memory. This tool has no access to any other \
                person's calendar. State only events that literally appear in this tool's \
                result — if event_count is 0, say the user's schedule is free instead of \
                inventing an event.
                """,
            parameters: [
                RAToolParameter(
                    name: "date",
                    type: .string,
                    description: """
                        Which period to check. Accepts a keyword — "today" (default), \
                        "tomorrow", "this_week", "next_7_days" — OR a specific day as \
                        "YYYY-MM-DD". For a custom multi-day range, use start_date/end_date \
                        instead of this field.
                        """,
                    required: false
                ),
                RAToolParameter(
                    name: "start_date",
                    type: .string,
                    description: """
                        Start of a specific custom date range, as "YYYY-MM-DD". When set, this \
                        overrides `date`. Pair with end_date for a multi-day range, or omit \
                        end_date to query just this one day.
                        """,
                    required: false
                ),
                RAToolParameter(
                    name: "end_date",
                    type: .string,
                    description: "End of the custom date range (inclusive), as \"YYYY-MM-DD\". Only used together with start_date.",
                    required: false
                )
            ],
            category: "Calendar"
        )
    }

    static var executor: ToolExecutor {
        { args in
            let date = args["date"]?.string
            let startDate = args["start_date"]?.string
            let endDate = args["end_date"]?.string
            do {
                return try await CalendarManager.shared.fetchEvents(
                    dateSpec: date,
                    startDate: startDate,
                    endDate: endDate
                )
            } catch {
                return ["error": RAToolValue(error.localizedDescription)]
            }
        }
    }
}
