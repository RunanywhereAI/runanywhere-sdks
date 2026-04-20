// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Public `RunAnywhere` VLM surface — richer result struct + legacy
// parameter-based overload.

import Foundation

/// Rich VLM result returned by the parameter-based `processImage`
/// overload. Includes timing + rough token counts for benchmark UI.
public struct VLMResult: Sendable {
    public let text: String
    public let totalTimeMs: Double
    public let tokensPerSecond: Double
    public let promptTokens: Int
    public let completionTokens: Int

    public init(text: String, totalTimeMs: Double, tokensPerSecond: Double,
                promptTokens: Int, completionTokens: Int) {
        self.text = text
        self.totalTimeMs = totalTimeMs
        self.tokensPerSecond = tokensPerSecond
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

@MainActor
public extension RunAnywhere {

    /// Legacy parameter-based `processImage` — bundles options +
    /// measures wall-clock time + approximates token counts from text
    /// length (~4 chars/token) for benchmark UI. Calls the canonical
    /// `processImage(_:prompt:options:)` entry point underneath.
    static func processImage(
        _ image: VLMImage,
        prompt: String,
        maxTokens: Int = 256,
        temperature: Float = 0.0
    ) async throws -> VLMResult {
        let start = Date()
        let opts = VLMGenerationOptions(maxTokens: maxTokens, temperature: temperature)
        let text = try await processImage(image, prompt: prompt, options: opts)
        let elapsed = Date().timeIntervalSince(start) * 1000
        let promptTok     = max(1, prompt.count / 4)
        let completionTok = max(1, text.count   / 4)
        let tps = elapsed > 0 ? Double(completionTok) / (elapsed / 1000) : 0
        return VLMResult(
            text: text,
            totalTimeMs: elapsed,
            tokensPerSecond: tps,
            promptTokens: promptTok,
            completionTokens: completionTok)
    }

    /// Cancel any in-flight VLM generation.
    static func cancelVLMGeneration() async {
        // Each `processImage` call today is self-contained — no
        // persistent VLM session is held. The cancel hook is exposed
        // for API parity with main.
    }
}
