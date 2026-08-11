//
//  ModelCompatibilityLookup.swift
//  RunAnywhereAI
//
//  Example-app helper that batch-queries commons model-fit via the Swift SDK
//  bridge. Returns an empty map when the SDK is not ready or a probe fails —
//  callers must not invent a local substitute budget.
//

import Foundation
import RunAnywhere

enum ModelCompatibilityLookup {
    /// Probe `can_run` for each id through `RunAnywhere.models.checkCompatibility`.
    /// Missing / failed probes are omitted (unknown), never replaced with a
    /// local size heuristic.
    static func canRunByModelID(for modelIDs: [String]) async -> [String: Bool] {
        guard RunAnywhere.isReady else { return [:] }
        var result: [String: Bool] = [:]
        for id in Set(modelIDs) where !id.isEmpty {
            do {
                let verdict = try await RunAnywhere.models.checkCompatibility(id: id)
                result[id] = verdict.canRun
            } catch {
                // Leave absent — unknown, not a fabricated fit.
                continue
            }
        }
        return result
    }
}
