//
//  CalendarTool.swift
//  RunAnywhereAI
//
//  Calendar tools — lets the on-device assistant answer simple questions
//  about the user's own schedule ("what's on my calendar today", "am I
//  free this week"), create events, and list the available calendars.
//  All three tools share CalendarManager and the single EventKit full-access
//  grant, so they are gated behind one Settings toggle.
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

    /// Requests full read/write access to Calendars. The same grant covers
    /// get_calendar_events (read), create_calendar_event (write), and
    /// list_calendars — EventKit does not offer a read-only grant.
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
                let startText = timeFormatter.string(from: event.startDate)
                timeText = "\(startText) - \(timeFormatter.string(from: event.endDate))"
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

    struct CalendarEventRequest: Sendable {
        let title: String
        let startSpec: String
        let endSpec: String?
        let durationMinutes: Int?
        let notes: String?
        let location: String?
        let calendarName: String?
    }

    private func eventCalendar(named name: String?) -> (calendar: EKCalendar?, error: String?) {
        guard let name, !name.isEmpty else {
            return (store.defaultCalendarForNewEvents, nil)
        }
        let writable = store.calendars(for: .event).filter(\.allowsContentModifications)
        guard let match = writable.first(where: {
            $0.title.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) else {
            let available = writable.map(\.title).joined(separator: ", ")
            return (nil, "No writable calendar named \"\(name)\". Writable calendars: \(available)")
        }
        return (match, nil)
    }

    private func resolveEventEnd(
        start: ToolDateParser.ParsedDate,
        endSpec: String?,
        durationMinutes: Int?
    ) -> (end: Date, error: String?) {
        if let endSpec, !endSpec.isEmpty {
            guard let parsedEnd = ToolDateParser.parse(endSpec), parsedEnd.date > start.date else {
                return (start.date, "end \"\(endSpec)\" must be a valid date-time after start")
            }
            return (parsedEnd.date, nil)
        }
        let minutes = max(durationMinutes ?? 60, 1)
        return (start.date.addingTimeInterval(TimeInterval(minutes) * 60), nil)
    }

    func createEvent(_ request: CalendarEventRequest) throws -> [String: RAToolValue] {
        guard let start = ToolDateParser.parse(request.startSpec) else {
            return [
                "error": RAToolValue(
                    "Could not parse start \"\(request.startSpec)\" — use \"YYYY-MM-DD HH:mm\" or \"YYYY-MM-DD\""
                )
            ]
        }
        let (calendar, calendarError) = eventCalendar(named: request.calendarName)
        if let calendarError {
            return ["error": RAToolValue(calendarError)]
        }
        guard let calendar else {
            return ["error": RAToolValue("No default calendar is configured on this device")]
        }

        let event = EKEvent(eventStore: store)
        event.title = request.title
        event.calendar = calendar
        if start.hasTime {
            let (end, endError) = resolveEventEnd(
                start: start,
                endSpec: request.endSpec,
                durationMinutes: request.durationMinutes
            )
            if let endError {
                return ["error": RAToolValue(endError)]
            }
            event.startDate = start.date
            event.endDate = end
        } else {
            event.isAllDay = true
            event.startDate = start.date
            event.endDate = start.date
        }
        if let notes = request.notes, !notes.isEmpty {
            event.notes = notes
        }
        if let location = request.location, !location.isEmpty {
            event.location = location
        }

        try store.save(event, span: .thisEvent, commit: true)

        return [
            "created": RAToolValue(true),
            "event_id": RAToolValue(event.eventIdentifier ?? ""),
            "title": RAToolValue(request.title),
            "start": RAToolValue(ToolDateParser.display(event.startDate, hasTime: start.hasTime)),
            "end": RAToolValue(ToolDateParser.display(event.endDate, hasTime: start.hasTime)),
            "calendar": RAToolValue(calendar.title)
        ]
    }

    func fetchCalendars() -> [String: RAToolValue] {
        let calendars = store.calendars(for: .event)
        let summaries = calendars.map { calendar in
            calendar.allowsContentModifications ? calendar.title : "\(calendar.title) (read-only)"
        }
        return [
            "calendar_count": RAToolValue(calendars.count),
            "calendars": RAToolValue(summaries.joined(separator: "; ")),
            "default_calendar": RAToolValue(store.defaultCalendarForNewEvents?.title ?? "none")
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
                ToolParameter(
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
                ToolParameter(
                    name: "start_date",
                    type: .string,
                    description: """
                        Start of a specific custom date range, as "YYYY-MM-DD". When set, this \
                        overrides `date`. Pair with end_date for a multi-day range, or omit \
                        end_date to query just this one day.
                        """,
                    required: false
                ),
                ToolParameter(
                    name: "end_date",
                    type: .string,
                    description: """
                        End of the custom date range (inclusive), as "YYYY-MM-DD". Only \
                        used together with start_date.
                        """,
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

// MARK: - create_calendar_event Tool

enum CalendarCreateTool {
    static var definition: RAToolDefinition {
        let todayString = CalendarManager.todayString
        return RAToolDefinition(
            name: "create_calendar_event",
            description: """
                Creates a new event in the user's own Calendar. Use only when the user \
                explicitly asks to schedule, book, or add something to their calendar \
                ("schedule a meeting tomorrow at 3pm", "put lunch with Sam on my \
                calendar") — never create an event as a side effect. Today's date is \
                \(todayString) — compute concrete dates for "tomorrow" or "next Tuesday" \
                from that, never from memory. Before picking a slot around existing \
                events, check availability with get_calendar_events; this tool does not \
                check for conflicts. On success the result contains event_id, the final \
                start/end, and the calendar used; if the result has "error", the event was \
                NOT created — report the error instead of claiming success.
                """,
            parameters: [
                ToolParameter(
                    name: "title",
                    type: .string,
                    description: "Event title as it should appear in the calendar, e.g. \"Lunch with Sam\"."
                ),
                ToolParameter(
                    name: "start",
                    type: .string,
                    description: """
                        Event start as "YYYY-MM-DD HH:mm" in the user's local time (e.g. \
                        "2026-08-12 15:00" for 3pm). Pass a bare "YYYY-MM-DD" to create an \
                        all-day event instead.
                        """
                ),
                ToolParameter(
                    name: "end",
                    type: .string,
                    description: """
                        Event end as "YYYY-MM-DD HH:mm", after start. Omit to use \
                        duration_minutes instead. Ignored for all-day events.
                        """,
                    required: false
                ),
                ToolParameter(
                    name: "duration_minutes",
                    type: .number,
                    description: """
                        Event length in minutes when "end" is not given. Defaults to 60. \
                        Ignored for all-day events.
                        """,
                    required: false
                ),
                ToolParameter(
                    name: "notes",
                    type: .string,
                    description: "Optional notes/description to attach to the event.",
                    required: false
                ),
                ToolParameter(
                    name: "location",
                    type: .string,
                    description: "Optional location, e.g. \"Cafe Roma\" or a street address.",
                    required: false
                ),
                ToolParameter(
                    name: "calendar_name",
                    type: .string,
                    description: """
                        Name of the calendar to add the event to, matching a name from \
                        list_calendars. Omit to use the user's default calendar — only set \
                        this when the user names a specific calendar.
                        """,
                    required: false
                )
            ],
            category: "Calendar"
        )
    }

    static var executor: ToolExecutor {
        { args in
            guard let title = args["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else {
                return ["error": RAToolValue("Missing required \"title\" argument")]
            }
            guard let startSpec = args["start"]?.string, !startSpec.isEmpty else {
                return ["error": RAToolValue("Missing required \"start\" argument")]
            }
            let request = CalendarManager.CalendarEventRequest(
                title: title,
                startSpec: startSpec,
                endSpec: args["end"]?.string,
                durationMinutes: args["duration_minutes"]?.int,
                notes: args["notes"]?.string,
                location: args["location"]?.string,
                calendarName: args["calendar_name"]?.string
            )
            do {
                return try await CalendarManager.shared.createEvent(request)
            } catch {
                return ["error": RAToolValue(error.localizedDescription)]
            }
        }
    }
}

// MARK: - list_calendars Tool

enum CalendarListTool {
    static var definition: RAToolDefinition {
        RAToolDefinition(
            name: "list_calendars",
            description: """
                Lists the calendars available on this device (e.g. "Home", "Work", \
                subscribed calendars), marking read-only ones, plus the default calendar \
                new events go to. Use before create_calendar_event when the user names a \
                specific calendar, or when they ask what calendars they have. Only name \
                calendars that literally appear in this result. Events cannot be created \
                on calendars marked read-only.
                """,
            parameters: [],
            category: "Calendar"
        )
    }

    static var executor: ToolExecutor {
        { _ in
            await CalendarManager.shared.fetchCalendars()
        }
    }
}
