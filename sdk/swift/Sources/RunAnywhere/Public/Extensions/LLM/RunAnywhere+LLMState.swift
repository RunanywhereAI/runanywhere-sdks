// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// LLM state accessors + unload convenience. These mirror the main branch's
// sample-facing shape: `isModelLoaded: Bool`, `getCurrentModelId() -> String?`
// (nullable), and an async `unloadModel()`.

import Foundation

public extension RunAnywhere {

    /// `true` when a model has been loaded via `loadModel(_:modelPath:…)`
    /// and not yet unloaded.
    static var isModelLoaded: Bool {
        SessionRegistry.currentLLM != nil &&
            !SessionRegistry.currentModelId.isEmpty
    }

    /// Current loaded model id — `nil` when no model is loaded. Main-branch
    /// sample call sites rely on optional semantics (`if let id = …`), so
    /// this overload exists alongside the String-returning one in
    /// `RunAnywhere+Lifecycle.swift` (which returns `""` for the same
    /// situation).
    static func getCurrentModelId() -> String? {
        SessionRegistry.currentModelId.isEmpty
            ? nil : SessionRegistry.currentModelId
    }

    /// Async overload of the existing synchronous `unloadModel()`.
    /// Matches the main-branch sample's `try await RunAnywhere.unloadModel()`
    /// call site. Swift resolves based on the async context at the call site.
    static func unloadModel() async throws {
        SessionRegistry.currentLLM = nil
        SessionRegistry.currentLLMChat = nil
        SessionRegistry.currentModelId = ""
        SessionRegistry.currentModelPath = ""
    }
}
