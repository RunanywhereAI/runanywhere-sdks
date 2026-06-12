//
//  RunAnywhere+ExampleShims.swift
//  RunAnywhereAI
//
//  App-local convenience helpers that don't belong in the SDK public surface.
//
//  All of the previous shim wrappers (modality-specific load/unload helpers,
//  current-model accessors, prompt-form generation overloads, VAD ergonomics,
//  VLM token-stream flattening, voice-agent compose helpers, URL-form
//  `registerModel`, etc.) have been promoted into the canonical SDK API.
//  The example app calls those directly via `RunAnywhere.*`.
//
//  What remains here is strictly example-specific UI plumbing that has no
//  cross-SDK parity story:
//
//    • `getRegisteredFrameworks()` — derives the framework filter list from
//      the model registry. Useful for the Models / Add-from-URL screens but
//      not part of the canonical cross-SDK spec.
//

import Foundation
import RunAnywhere

// MARK: - Framework Discovery (Example-Specific)

extension RunAnywhere {
    /// Compute the set of inference frameworks present in the model registry.
    ///
    /// Sorted by descending model count so the UI surfaces the most useful
    /// frameworks first. This is example-app-specific UI plumbing — it
    /// composes the canonical `RunAnywhere.listModels()` proto API into the
    /// shape the Models tab and Add-from-URL flow want, but does not belong
    /// in the SDK public surface.
    static func getRegisteredFrameworks() async -> [RAInferenceFramework] {
        let result = await listModels()
        guard result.success else { return [] }
        var counts: [RAInferenceFramework: Int] = [:]
        for model in result.models.models where model.framework != .unspecified {
            counts[model.framework, default: 0] += 1
        }
        let frameworks = counts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key.displayName < rhs.key.displayName
        }
        return frameworks.map(\.key)
    }
}
