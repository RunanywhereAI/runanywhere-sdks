//
//  HealthKitTool.swift
//  RunAnywhereAI
//
//  Apple Health tool — lets the on-device assistant answer questions about
//  the user's own activity, vitals, body measurements, and wellbeing data,
//  for any specific day or custom date range.
//

import Foundation
import RunAnywhere

// HealthKit only exists on iOS (and watchOS/Catalyst) — this app also ships
// as a native macOS target, which has no HealthKit.framework at all.
#if os(iOS)
import HealthKit

// MARK: - HealthKit Manager

/// Read-only HealthKit access for the `get_health_data` tool. Actor-isolated
/// because HKHealthStore's completion handlers land on background queues.
actor HealthKitManager {
    static let shared = HealthKitManager()

    private let store = HKHealthStore()

    enum HealthKitToolError: LocalizedError {
        case notAvailable
        case unknownMetric(String)

        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "Health data is not available on this device."
            case .unknownMetric(let metric):
                return "Unknown health metric: \(metric)"
            }
        }
    }

    // Read-only types this tool ever asks for. Kept in one place so the
    // authorization request and the app's usage-description string
    // (Info.plist NSHealthShareUsageDescription) stay honest about scope.
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .environmentalAudioExposure)!,
            HKObjectType.quantityType(forIdentifier: .headphoneAudioExposure)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
            HKObjectType.quantityType(forIdentifier: .vo2Max)!,
            HKObjectType.quantityType(forIdentifier: .flightsClimbed)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .height)!,
            HKObjectType.quantityType(forIdentifier: .bodyMassIndex)!,
            HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!,
            HKObjectType.quantityType(forIdentifier: .bodyTemperature)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!,
            HKObjectType.activitySummaryType()
        ]
        types.insert(HKObjectType.workoutType())
        return types
    }

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Requests read access for every type this tool can query. HealthKit
    /// deliberately never reports per-type grant/deny back to the app (a
    /// privacy design choice) — this only throws for device-level
    /// unavailability, not for the user declining individual permissions in
    /// the system sheet. A denied read simply comes back as "no samples"
    /// later, which every fetcher below already treats as a valid,
    /// zero-value result rather than an error.
    func requestAuthorization() async throws {
        guard HealthKitManager.isAvailable else {
            throw HealthKitToolError.notAvailable
        }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// A resolved query window plus the label to echo back to the model, so
    /// it doesn't have to re-derive "today"/"last_7_days" from raw dates.
    private struct HealthDateRange {
        let start: Date
        let end: Date
        let label: String
    }

    fileprivate static let isoDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        // Fixed POSIX locale + device time zone: parses/formats calendar
        // days the way the user experiences them, independent of the
        // device's region settings (which could otherwise reorder
        // day/month or use a non-Gregorian calendar).
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        return formatter
    }()

    private func parseISODay(_ string: String) -> Date? {
        HealthKitManager.isoDayFormatter.date(from: string)
    }

    /// Resolves the request's date arguments into a concrete query window.
    /// Priority: an explicit range start (optionally paired with an end)
    /// always wins, so the model can ask about any specific day or custom
    /// range ("2026-06-01" to "2026-06-14"). Otherwise `dateSpec` is checked
    /// against the keyword shortcuts ("today"/"yesterday"/"last_7_days"/
    /// "last_30_days") and, failing that, parsed as a single explicit day.
    /// Falls back to "today" only when nothing given is recognizable.
    ///
    /// The range start is read from `startDate` OR — if that's missing but
    /// `endDate` is present — from `dateSpec` itself. Models don't reliably
    /// follow the "pair start_date with end_date" instruction; a common
    /// observed mistake is putting the range's start day in `date` and only
    /// the end in `end_date` (e.g. `{"date": "2026-03-01", "end_date":
    /// "2026-03-20"}` instead of using `start_date`). Treating any explicit
    /// day paired with an `end_date` as a range start — regardless of which
    /// field it arrived in — makes the tool work with what the model
    /// actually sends instead of what its description merely asks for.
    private func resolveRange(dateSpec: String?, startDate: String?, endDate: String?) -> HealthDateRange {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        // Health data cannot exist for a day that hasn't happened yet.
        // Small models occasionally hand-type a future date despite the
        // tool description anchoring "today" for them (observed: a model
        // asked for "today" once produced "2024-01-01" — the same failure
        // mode can just as easily land in the future). Clamping here is a
        // second line of defense that doesn't depend on the model getting
        // the prompt guidance right.
        func clampToToday(_ date: Date) -> Date { min(date, now) }

        let effectiveStartDate = startDate ?? (endDate != nil ? dateSpec : nil)
        if let effectiveStartDate, let parsedStart = parseISODay(effectiveStartDate) {
            let startDate = effectiveStartDate
            let startDay = calendar.startOfDay(for: clampToToday(parsedStart))
            let endDay: Date
            let label: String
            if let endDate, let parsedEnd = parseISODay(endDate), parsedEnd != parsedStart {
                let clampedEndDay = calendar.startOfDay(for: clampToToday(parsedEnd))
                endDay = calendar.date(byAdding: .day, value: 1, to: clampedEndDay) ?? startDay
                label = "\(startDate) to \(endDate)"
            } else {
                endDay = calendar.date(byAdding: .day, value: 1, to: startDay) ?? startDay
                label = startDate
            }
            return HealthDateRange(start: startDay, end: max(endDay, startDay), label: label)
        }

        switch dateSpec?.lowercased() {
        case "yesterday":
            let start = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
            return HealthDateRange(start: start, end: startOfToday, label: "yesterday")
        case "last_7_days":
            let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return HealthDateRange(start: start, end: now, label: "last_7_days")
        case "last_30_days":
            let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            return HealthDateRange(start: start, end: now, label: "last_30_days")
        case "today", .none:
            let end = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
            return HealthDateRange(start: startOfToday, end: end, label: "today")
        case .some(let explicitDay):
            // Not a keyword — try it as a single explicit "YYYY-MM-DD" day
            // (covers models that pass a date through `date` instead of
            // `start_date`).
            if let parsed = parseISODay(explicitDay) {
                let day = calendar.startOfDay(for: clampToToday(parsed))
                let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
                return HealthDateRange(start: day, end: end, label: explicitDay)
            }
            let end = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
            return HealthDateRange(start: startOfToday, end: end, label: "today")
        }
    }

    /// Dispatches to the right fetcher for `metric`, resolving the date
    /// arguments into a query window (see `resolveRange`).
    func fetch(
        metric: String,
        dateSpec: String?,
        startDate: String? = nil,
        endDate: String? = nil
    ) async throws -> [String: RAToolValue] {
        let range = resolveRange(dateSpec: dateSpec, startDate: startDate, endDate: endDate)
        switch metric.lowercased() {
        case "steps":
            return try await fetchSteps(range: range)
        case "active_energy":
            return try await fetchActiveEnergy(range: range)
        case "heart_rate":
            return try await fetchHeartRate(range: range)
        case "distance":
            return try await fetchDistance(range: range)
        case "sleep":
            return try await fetchSleep(range: range)
        case "workouts":
            return try await fetchWorkouts(range: range)
        case "noise_exposure":
            return try await fetchNoiseExposure(range: range)
        case "activity_rings":
            return try await fetchActivityRings(range: range)
        case "resting_heart_rate":
            return try await fetchAverage(
                identifier: .restingHeartRate, key: "resting_bpm",
                unit: HKUnit.count().unitDivided(by: .minute()), range: range
            )
        case "heart_rate_variability":
            return try await fetchAverage(
                identifier: .heartRateVariabilitySDNN, key: "hrv_ms",
                unit: HKUnit.secondUnit(with: .milli), range: range
            )
        case "blood_oxygen":
            return try await fetchAverage(
                identifier: .oxygenSaturation, key: "spo2_percent",
                unit: HKUnit.percent(), range: range, scale: 100
            )
        case "respiratory_rate":
            return try await fetchAverage(
                identifier: .respiratoryRate, key: "breaths_per_minute",
                unit: HKUnit.count().unitDivided(by: .minute()), range: range
            )
        case "vo2_max":
            let vo2MaxUnit = HKUnit.literUnit(with: .milli)
                .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
            return try await fetchAverage(identifier: .vo2Max, key: "vo2_max_ml_kg_min", unit: vo2MaxUnit, range: range)
        case "flights_climbed":
            return try await fetchSum(identifier: .flightsClimbed, key: "flights", unit: .count(), range: range)
        case "weight":
            return try await fetchAverage(
                identifier: .bodyMass, key: "weight_kg", unit: HKUnit.gramUnit(with: .kilo), range: range
            )
        case "height":
            return try await fetchAverage(
                identifier: .height, key: "height_cm", unit: HKUnit.meterUnit(with: .centi), range: range
            )
        case "bmi":
            return try await fetchAverage(identifier: .bodyMassIndex, key: "bmi", unit: .count(), range: range)
        case "body_fat_percentage":
            return try await fetchAverage(
                identifier: .bodyFatPercentage, key: "body_fat_percent",
                unit: HKUnit.percent(), range: range, scale: 100
            )
        case "body_temperature":
            return try await fetchAverage(
                identifier: .bodyTemperature, key: "temperature_celsius", unit: HKUnit.degreeCelsius(), range: range
            )
        case "mindful_minutes":
            return try await fetchMindfulMinutes(range: range)
        default:
            throw HealthKitToolError.unknownMetric(metric)
        }
    }

    /// Cumulative quantities (steps, calories, flights climbed, ...): total
    /// over the whole range.
    private func fetchSum(
        identifier: HKQuantityTypeIdentifier, key: String, unit: HKUnit, range: HealthDateRange
    ) async throws -> [String: RAToolValue] {
        let type = HKQuantityType.quantityType(forIdentifier: identifier)!
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end)
        let value = try await sumQuantity(type: type, predicate: predicate, unit: unit)
        return [key: RAToolValue(value), "date": RAToolValue(range.label)]
    }

    /// Point-in-time quantities (weight, resting heart rate, SpO2, ...):
    /// averaged over the range. `scale` converts HealthKit's 0-1 fraction
    /// units (percent-based ones like oxygen saturation) into a human-scale
    /// number — 87% is far less error-prone for a model to report than 0.87.
    private func fetchAverage(
        identifier: HKQuantityTypeIdentifier, key: String, unit: HKUnit, range: HealthDateRange, scale: Double = 1
    ) async throws -> [String: RAToolValue] {
        let type = HKQuantityType.quantityType(forIdentifier: identifier)!
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end)
        let value = try await averageQuantity(type: type, predicate: predicate, unit: unit)
        return [key: RAToolValue(value * scale), "date": RAToolValue(range.label)]
    }

    private func fetchSteps(range: HealthDateRange) async throws -> [String: RAToolValue] {
        try await fetchSum(identifier: .stepCount, key: "steps", unit: .count(), range: range)
    }

    private func fetchActiveEnergy(range: HealthDateRange) async throws -> [String: RAToolValue] {
        try await fetchSum(identifier: .activeEnergyBurned, key: "active_energy_kcal", unit: .kilocalorie(), range: range)
    }

    private func fetchHeartRate(range: HealthDateRange) async throws -> [String: RAToolValue] {
        let type = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end)
        let unit = HKUnit.count().unitDivided(by: .minute())

        let (average, minimum, maximum) = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<(Double, Double, Double), Error>) in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: [.discreteAverage, .discreteMin, .discreteMax]
            ) { _, stats, error in
                if let error, !self.isNoDataError(error) {
                    continuation.resume(throwing: error)
                    return
                }
                let avg = stats?.averageQuantity()?.doubleValue(for: unit) ?? 0
                let min = stats?.minimumQuantity()?.doubleValue(for: unit) ?? 0
                let max = stats?.maximumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: (avg, min, max))
            }
            store.execute(query)
        }

        return [
            "average_bpm": RAToolValue(average),
            "min_bpm": RAToolValue(minimum),
            "max_bpm": RAToolValue(maximum),
            "date": RAToolValue(range.label)
        ]
    }

    private func fetchDistance(range: HealthDateRange) async throws -> [String: RAToolValue] {
        try await fetchSum(
            identifier: .distanceWalkingRunning, key: "distance_km", unit: HKUnit.meterUnit(with: .kilo), range: range
        )
    }

    private func fetchWorkouts(range: HealthDateRange) async throws -> [String: RAToolValue] {
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end)

        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (results as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }

        let summaries = workouts.map { workout -> String in
            let minutes = Int(workout.duration / 60)
            let kcal = workout.statistics(for: HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!)?
                .sumQuantity()?.doubleValue(for: .kilocalorie())
            let kcalText = kcal.map { ", \(Int($0)) kcal" } ?? ""
            return "\(workout.workoutActivityType.name) — \(minutes) min\(kcalText)"
        }

        return [
            "workout_count": RAToolValue(Double(workouts.count)),
            "workouts": RAToolValue(summaries.joined(separator: "; ")),
            "date": RAToolValue(range.label)
        ]
    }

    private func fetchSleep(range: HealthDateRange) async throws -> [String: RAToolValue] {
        let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        // A night's sleep starts well before midnight of the day it's
        // attributed to, so widen the query window backward instead of
        // using the same start the other metrics query with.
        let queryStart = Calendar.current.date(byAdding: .hour, value: -12, to: range.start) ?? range.start
        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: range.end)

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        // TODO(human): Aggregate `samples` into a total-sleep-duration result.
        //
        // Each sample is one HealthKit-recorded sleep segment:
        //   - sample.value is an HKCategoryValueSleepAnalysis raw value:
        //     .inBed, .asleepUnspecified, .asleepCore, .asleepDeep,
        //     .asleepREM, or .awake
        //   - sample.startDate / sample.endDate give that segment's span
        //
        // Decide which values count as "asleep" time (note: .inBed does NOT
        // mean asleep — it can include time spent awake in bed), sum the
        // duration of the segments you count, and return a dict such as:
        //   ["hours_asleep": RAToolValue(...), "segment_count": RAToolValue(...),
        //    "date": RAToolValue(range.label)]
        // Handle the empty-samples case (no data / no permission) by
        // returning zeros rather than throwing — HealthKit can't distinguish
        // "no permission" from "no data" for reads, so treating both the
        // same way here is the only option. Returning an empty dict here is
        // NOT a safe placeholder — always include at least "date" so the
        // model has something to reason about.
        return ["date": RAToolValue(range.label)]
    }

    /// Sums Mindfulness app session durations. Unlike sleep, a mindful
    /// session's category value carries no sub-classification worth
    /// distinguishing — every recorded session counts, so this needs no
    /// judgment call the way `fetchSleep` does.
    private func fetchMindfulMinutes(range: HealthDateRange) async throws -> [String: RAToolValue] {
        let type = HKCategoryType.categoryType(forIdentifier: .mindfulSession)!
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end)

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        let totalMinutes = samples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) / 60 }
        return [
            "mindful_minutes": RAToolValue(totalMinutes),
            "session_count": RAToolValue(Double(samples.count)),
            "date": RAToolValue(range.label)
        ]
    }

    private func fetchNoiseExposure(range: HealthDateRange) async throws -> [String: RAToolValue] {
        let dbUnit = HKUnit.decibelAWeightedSoundPressureLevel()
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end)
        async let environmental = averageQuantity(
            type: HKQuantityType.quantityType(forIdentifier: .environmentalAudioExposure)!,
            predicate: predicate,
            unit: dbUnit
        )
        async let headphone = averageQuantity(
            type: HKQuantityType.quantityType(forIdentifier: .headphoneAudioExposure)!,
            predicate: predicate,
            unit: dbUnit
        )
        let (environmentalDb, headphoneDb) = try await (environmental, headphone)
        return [
            "environmental_avg_db": RAToolValue(environmentalDb),
            "headphone_avg_db": RAToolValue(headphoneDb),
            "date": RAToolValue(range.label)
        ]
    }

    /// Builds an OR-of-single-day predicates for `HKActivitySummaryQuery`,
    /// which — unlike every other query here — has no start/end-date
    /// predicate helper, only a per-day one. Capped at 31 days so an
    /// oversized custom range can't build an unbounded predicate list.
    private func activitySummaryPredicate(for range: HealthDateRange) -> NSPredicate {
        let calendar = Calendar.current
        var day = range.start
        var predicates: [NSPredicate] = []
        var daysAdded = 0
        while day < range.end, daysAdded < 31 {
            var components = calendar.dateComponents([.year, .month, .day, .era], from: day)
            components.calendar = calendar
            predicates.append(HKQuery.predicateForActivitySummary(with: components))
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? range.end
            daysAdded += 1
        }
        return NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
    }

    /// Move/exercise/stand ring totals — the source data behind the Fitness
    /// app's activity rings. Summed across every day in `range` rather than
    /// just returning the last day, so "how has my activity been this week"
    /// gets one meaningful answer instead of the model having to call this
    /// tool seven times.
    private func fetchActivityRings(range: HealthDateRange) async throws -> [String: RAToolValue] {
        let predicate = activitySummaryPredicate(for: range)
        let summaries: [HKActivitySummary] = try await withCheckedThrowingContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: results ?? [])
            }
            store.execute(query)
        }

        guard !summaries.isEmpty else {
            return ["days_with_data": RAToolValue(0.0), "date": RAToolValue(range.label)]
        }

        let kcalUnit = HKUnit.kilocalorie()
        let minuteUnit = HKUnit.minute()
        let countUnit = HKUnit.count()
        var moveKcal = 0.0, moveGoalKcal = 0.0
        var exerciseMinutes = 0.0, exerciseGoalMinutes = 0.0
        var standHours = 0.0, standGoalHours = 0.0
        var perfectDays = 0

        for summary in summaries {
            let move = summary.activeEnergyBurned.doubleValue(for: kcalUnit)
            let moveGoal = summary.activeEnergyBurnedGoal.doubleValue(for: kcalUnit)
            let exercise = summary.appleExerciseTime.doubleValue(for: minuteUnit)
            let exerciseGoal = summary.appleExerciseTimeGoal.doubleValue(for: minuteUnit)
            let stand = summary.appleStandHours.doubleValue(for: countUnit)
            let standGoal = summary.appleStandHoursGoal.doubleValue(for: countUnit)

            moveKcal += move
            moveGoalKcal += moveGoal
            exerciseMinutes += exercise
            exerciseGoalMinutes += exerciseGoal
            standHours += stand
            standGoalHours += standGoal
            if moveGoal > 0, move >= moveGoal, exercise >= exerciseGoal, stand >= standGoal {
                perfectDays += 1
            }
        }

        return [
            "days_with_data": RAToolValue(Double(summaries.count)),
            "perfect_days": RAToolValue(Double(perfectDays)),
            "move_kcal": RAToolValue(moveKcal),
            "move_goal_kcal": RAToolValue(moveGoalKcal),
            "exercise_minutes": RAToolValue(exerciseMinutes),
            "exercise_goal_minutes": RAToolValue(exerciseGoalMinutes),
            "stand_hours": RAToolValue(standHours),
            "stand_goal_hours": RAToolValue(standGoalHours),
            "date": RAToolValue(range.label)
        ]
    }

    /// `HKStatisticsQuery` doesn't always resolve "nothing recorded in this
    /// window" the way `HKSampleQuery` does (an empty result array) — for
    /// some quantity types it instead completes with an actual `HKError
    /// .errorNoData`. That's not a failure from this tool's point of view;
    /// it's the same answer as "0 samples", so every call site below treats
    /// it as zero instead of surfacing an "error" the model has to explain
    /// away to the user.
    private nonisolated func isNoDataError(_ error: Error) -> Bool {
        (error as? HKError)?.code == .errorNoData
    }

    private func sumQuantity(type: HKQuantityType, predicate: NSPredicate, unit: HKUnit) async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, error in
                if let error, !self.isNoDataError(error) {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(query)
        }
    }

    private func averageQuantity(type: HKQuantityType, predicate: NSPredicate, unit: HKUnit) async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, stats, error in
                if let error, !self.isNoDataError(error) {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(query)
        }
    }
}

private extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .yoga: return "Yoga"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Strength Training"
        case .hiking: return "Hiking"
        default: return "Workout"
        }
    }
}

// MARK: - get_health_data Tool

enum HealthKitTool {
    // `definition` is computed (not a stored `let`) so the description
    // always embeds *today's actual date*. Small on-device models have no
    // real notion of "now" and will otherwise confidently invent a wrong
    // one (observed in testing: a model asked for "today" produced
    // "2024-01-01" out of thin air). Anchoring the tool description itself
    // to a concrete, correct date — and steering the model toward the
    // keyword shortcuts instead of hand-typing a date — is the same fix
    // already used for get_current_time's "don't re-derive time yourself"
    // guidance above.
    static var definition: RAToolDefinition {
        let todayString = HealthKitManager.isoDayFormatter.string(from: Date())
        return RAToolDefinition(
            name: "get_health_data",
            description: """
                Gets the user's own Apple Health data: activity (steps, active energy, \
                distance, flights climbed, workouts, Activity ring move/exercise/stand \
                progress), vitals (heart rate, resting heart rate, heart rate \
                variability, blood oxygen, respiratory rate, VO2 max, body \
                temperature), body measurements (weight, height, BMI, body fat \
                percentage), and wellbeing (sleep, mindful minutes, noise exposure). \
                Today's date is \(todayString) — use that as your only source of truth \
                for "today", never guess or recall a date from memory. Supports any \
                specific day or custom date range, not just today. Use this whenever \
                the user asks about their own health, fitness, body, or wellbeing \
                (e.g. "how did I sleep last night", "how many steps did I take \
                between June 1st and June 14th", "did I close my rings this week", \
                "what's my resting heart rate", "how much have I weighed lately"). \
                For a whole named month (e.g. "how many steps in March"), set \
                start_date to that month's 1st and end_date to its last day — \
                always set BOTH together, never end_date alone. This tool has no \
                access to any other person's data. IMPORTANT: only state numbers \
                that literally appear as fields in this tool's JSON result. If the \
                field you need is missing or the value is 0, that means the data is \
                genuinely unavailable — say so honestly ("I don't have that data") \
                instead of estimating, guessing, or inventing a plausible-sounding \
                number.
                """,
            parameters: [
                RAToolParameter(
                    name: "metric",
                    type: .string,
                    description: "Which health metric to retrieve",
                    required: true,
                    enumValues: [
                        "steps", "sleep", "heart_rate", "resting_heart_rate", "heart_rate_variability",
                        "active_energy", "distance", "workouts", "noise_exposure", "activity_rings",
                        "blood_oxygen", "respiratory_rate", "vo2_max", "flights_climbed",
                        "weight", "height", "bmi", "body_fat_percentage", "body_temperature",
                        "mindful_minutes"
                    ]
                ),
                RAToolParameter(
                    name: "date",
                    type: .string,
                    description: """
                        Which period to retrieve data for. STRONGLY PREFER one of the keywords — \
                        "today" (default), "yesterday", "last_7_days", "last_30_days" — since \
                        those are computed correctly for you. Only pass an explicit \
                        "YYYY-MM-DD" day when the user names a real calendar date (e.g. "June \
                        14th", "my birthday on the 3rd") — never invent, guess, or recall a date \
                        from memory; every date you type here must be derived from today's date \
                        (\(todayString)) stated above or from a date the user explicitly gave \
                        you. For a custom multi-day range, use start_date/end_date instead of \
                        this field.
                        """,
                    required: false
                ),
                RAToolParameter(
                    name: "start_date",
                    type: .string,
                    description: """
                        Start of a specific custom date range, as "YYYY-MM-DD", derived from \
                        today's date (\(todayString)) or a date the user explicitly named — \
                        never guessed. When set, this overrides `date`. Pair with end_date for \
                        a multi-day range, or omit end_date to query just this one day.
                        """,
                    required: false
                ),
                RAToolParameter(
                    name: "end_date",
                    type: .string,
                    description: """
                        End of the custom date range (inclusive), as "YYYY-MM-DD". Only used \
                        together with start_date; same rule applies — derive it from today's \
                        date (\(todayString)) or the user's own words, never guess.
                        """,
                    required: false
                )
            ],
            category: "Health"
        )
    }

    static var executor: ToolExecutor {
        { args in
            guard let metric = args["metric"]?.string else {
                return ["error": RAToolValue("Missing required argument: metric")]
            }
            let date = args["date"]?.string
            let startDate = args["start_date"]?.string
            let endDate = args["end_date"]?.string
            do {
                return try await HealthKitManager.shared.fetch(
                    metric: metric,
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
#endif
