//
//  WorkflowScheduler.swift
//  RunAnywhereAI
//
//  The host clock behind ScheduleTriggerConfig. Commons validates and runs the
//  graph but deliberately owns no timer, because a timer that survives sleep
//  and relaunch is a platform concern.
//
//  Scope, stated plainly: this fires while the app is running. There is no
//  background execution and no persistence of fire times across launches — a
//  schedule's clock restarts when the app does. Cron is stored and round-trips
//  through the document, but nothing here parses it, so a cron trigger is
//  listed as unscheduled rather than silently ignored.
//
//  Owned as a single app-level instance rather than by the canvas: closing the
//  workflow editor must not stop the schedules the user set up in it.
//

import Foundation
import Observation
import RunAnywhere

@MainActor
@Observable
final class WorkflowScheduler {
    static let shared = WorkflowScheduler()

    struct Entry: Identifiable, Equatable {
        let workflowID: String
        var name: String
        var kind: RAScheduleKind
        var summary: String
        var nextFireDate: Date?
        var lastFireDate: Date?
        var isEnabled: Bool
        var lastOutcome: String?

        var id: String { workflowID }

        var isScheduled: Bool { nextFireDate != nil }
    }

    private(set) var entries: [Entry] = []
    private(set) var isActive = false

    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var activeRuns: [String: WorkflowRun] = [:]
    @ObservationIgnored private var disabledIDs: Set<String>

    /// A coarse tick rather than a sleep to the exact due moment: it keeps the
    /// countdown in the list honest and it costs nothing at this scale.
    private static let tickSeconds = 15

    private static let disabledDefaultsKey = "workflows.scheduler.disabled"

    private init() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.disabledDefaultsKey) ?? []
        disabledIDs = Set(stored)
    }

    // MARK: - Lifecycle

    func start() {
        guard tickTask == nil else { return }
        isActive = true
        tickTask = Task { [weak self] in
            await self?.reload()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.tickSeconds))
                guard !Task.isCancelled else { return }
                await self?.fireDue()
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
        isActive = false
    }

    // MARK: - Catalogue

    /// Rescan the stored workflows for schedule triggers. Called on start and
    /// whenever the editor saves, so a schedule takes effect without a relaunch.
    func reload() async {
        guard let summaries = try? await RunAnywhere.workflows.list() else { return }

        var rebuilt: [Entry] = []
        for summary in summaries {
            guard let document = try? await RunAnywhere.workflows.load(id: summary.id),
                  let config = scheduleConfig(in: document) else { continue }

            let previous = entries.first { $0.workflowID == summary.id }
            var entry = Entry(
                workflowID: summary.id,
                name: document.name,
                kind: config.kind,
                summary: Self.summary(of: config),
                nextFireDate: nil,
                lastFireDate: previous?.lastFireDate,
                isEnabled: !disabledIDs.contains(summary.id),
                lastOutcome: previous?.lastOutcome
            )
            entry.nextFireDate = Self.nextFireDate(
                for: config, after: entry.lastFireDate ?? Date(), now: Date()
            )
            rebuilt.append(entry)
        }
        entries = rebuilt.sorted { left, right in
            switch (left.nextFireDate, right.nextFireDate) {
            case let (lhs?, rhs?): return lhs == rhs ? left.name < right.name : lhs < rhs
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return left.name < right.name
            }
        }
    }

    func setEnabled(_ enabled: Bool, for workflowID: String) {
        if enabled {
            disabledIDs.remove(workflowID)
        } else {
            disabledIDs.insert(workflowID)
        }
        UserDefaults.standard.set(Array(disabledIDs).sorted(), forKey: Self.disabledDefaultsKey)
        guard let index = entries.firstIndex(where: { $0.workflowID == workflowID }) else { return }
        entries[index].isEnabled = enabled
    }

    func runNow(_ workflowID: String) async {
        await fire(workflowID)
    }

    private func scheduleConfig(in document: RAWorkflowDocument) -> RAScheduleTriggerConfig? {
        for node in document.nodes {
            if case .scheduleTrigger(let config) = node.config { return config }
        }
        return nil
    }

    // MARK: - Firing

    private func fireDue() async {
        let now = Date()
        let due = entries.filter { entry in
            entry.isEnabled && (entry.nextFireDate.map { $0 <= now } ?? false)
        }
        guard !due.isEmpty else { return }

        for entry in due {
            guard let index = entries.firstIndex(where: { $0.workflowID == entry.workflowID })
            else { continue }
            entries[index].lastFireDate = now
            await fire(entry.workflowID)
        }
        await reload()
    }

    private func fire(_ workflowID: String) async {
        do {
            let run = try await RunAnywhere.workflows.run(workflowID: workflowID)
            activeRuns[workflowID]?.destroy()
            activeRuns[workflowID] = run
            record(workflowID, outcome: "Running…")

            Task { [weak self] in
                for await event in run.events {
                    guard case .runFinished(let finished) = event.event else { continue }
                    self?.settle(workflowID, run: run, finished: finished)
                }
            }
            try run.start()
        } catch {
            record(workflowID, outcome: error.localizedDescription)
        }
    }

    /// Only retires the run that finished. A second firing while the first is
    /// still draining would otherwise destroy the live one.
    private func settle(_ workflowID: String, run: WorkflowRun, finished: RARunFinished) {
        switch finished.state {
        case .succeeded:
            record(workflowID, outcome: "Last run succeeded")
        case .failed:
            record(workflowID, outcome: finished.hasError ? finished.error.message : "Last run failed")
        case .cancelled:
            record(workflowID, outcome: "Last run was cancelled")
        case .running, .unspecified, .UNRECOGNIZED:
            break
        }
        guard activeRuns[workflowID] === run else { return }
        activeRuns.removeValue(forKey: workflowID)?.destroy()
    }

    private func record(_ workflowID: String, outcome: String) {
        guard let index = entries.firstIndex(where: { $0.workflowID == workflowID }) else { return }
        entries[index].lastOutcome = outcome
    }

    // MARK: - Clock

    static func summary(of config: RAScheduleTriggerConfig) -> String {
        switch config.kind {
        case .daily:
            return String(format: "Every day at %02d:%02d", config.hour, config.minute)
        case .cron:
            return config.cron.isEmpty ? "Cron expression not set" : "Cron: \(config.cron)"
        case .interval, .unspecified, .UNRECOGNIZED:
            return "Every " + WorkflowScheduleFormat.interval(seconds: Int(config.intervalSeconds))
        }
    }

    /// Cron returns nil: this host has no cron parser, and guessing a fire time
    /// for an expression it cannot read would be worse than saying so.
    static func nextFireDate(
        for config: RAScheduleTriggerConfig,
        after reference: Date,
        now: Date
    ) -> Date? {
        switch config.kind {
        case .cron:
            return nil
        case .daily:
            var components = DateComponents()
            components.hour = Int(min(23, config.hour))
            components.minute = Int(min(59, config.minute))
            return Calendar.current.nextDate(
                after: now, matching: components, matchingPolicy: .nextTime
            )
        case .interval, .unspecified, .UNRECOGNIZED:
            let seconds = TimeInterval(max(1, config.intervalSeconds))
            var candidate = reference.addingTimeInterval(seconds)
            if candidate <= now {
                let missed = (now.timeIntervalSince(candidate) / seconds).rounded(.down) + 1
                candidate = candidate.addingTimeInterval(missed * seconds)
            }
            return candidate
        }
    }
}
