// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Extensions on LLMGenerationResult matching main's rich result fields
// used by the iOS sample's analytics / benchmark UI.

import Foundation

public extension LLMGenerationResult {
    /// Framework name string inferred from `modelUsed` via the catalog.
    /// Off-actor-safe; sample analytics use this for the framework
    /// column. Returns `nil` when no catalog entry is available so the
    /// caller can fall back to the model's own framework.
    var framework: String? { nil }

    /// Rough prompt-token count. v2 reports `tokensUsed` as the total;
    /// `inputTokens` and `responseTokens` each report an approximation.
    var inputTokens: Int { 0 }
    var responseTokens: Int { tokensUsed }
    var thinkingTokens: Int { 0 }
    var thinkingContent: String { "" }
}

// LLMStreamingResult.result is now a canonical stored `Task<_, Error>` on
// the struct itself so callers can `await result.value`. See
// `RunAnywhere+Lifecycle.swift`.
