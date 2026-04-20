// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Main-branch-shaped Diffusion entry points:
//   loadDiffusionModel(modelPath:modelId:modelName:configuration:) async throws
//   generateImage(prompt:options:progress:)

import Foundation

@MainActor
public extension RunAnywhere {

    /// Main-branch parity loader — parameter order swapped to put path
    /// first and adds a `modelName` field that's purely cosmetic here.
    /// Bridges onto the canonical `(id, path, format, configuration)` form.
    static func loadDiffusionModel(
        modelPath: String,
        modelId: String,
        modelName: String,
        configuration: DiffusionConfiguration = .init()
    ) async throws {
        _ = modelName   // retained for call-site symmetry; logged nowhere yet
        try loadDiffusionModel(modelId,
                                modelPath: modelPath,
                                format: .coreML,
                                configuration: configuration)
    }

    /// Progress-aware image generation with `DiffusionProgress` deltas.
    /// The closure returns `Bool` — `true` continues, `false` cancels.
    /// Current implementation runs sync and fires a single final tick;
    /// real per-step streaming lands once the diffusion engine exposes
    /// a per-step callback via the C ABI.
    @discardableResult
    static func generateImage(
        prompt: String,
        options: DiffusionGenerationOptions = .init(),
        progress: ((DiffusionProgress) -> Bool)? = nil
    ) async throws -> DiffusionResult {
        let result = try await generateImage(
            DiffusionRequest(prompt: prompt, options: options))
        if let progress {
            _ = progress(DiffusionProgress(currentStep: 25, totalSteps: 25))
        }
        return result
    }
}
