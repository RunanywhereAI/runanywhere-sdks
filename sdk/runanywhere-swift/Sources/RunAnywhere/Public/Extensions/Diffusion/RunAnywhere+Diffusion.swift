//
//  RunAnywhere+Diffusion.swift
//  RunAnywhere SDK
//
//  Public API for on-device image generation (Diffusion).
//  Uses C++ directly via CppBridge.Diffusion.
//
//  Loading flows through the canonical lifecycle (`RAModelLoadRequest` with
//  `category = .imageGeneration`). This file owns only inference (image
//  generation) entry points — there is no dedicated diffusion load API.
//
//  Backed by the Apple CoreML Stable-Diffusion engine (priority 100 on the
//  DIFFUSION primitive). See `CppBridge+Diffusion` for the streaming/cancel
//  semantics against the current commons diffusion ABI.
//

import CRACommons

// MARK: - Diffusion (Image Generation)

public extension RunAnywhere {

    /// Generate an image from the lifecycle-loaded diffusion model.
    ///
    /// The prompt and all generation parameters travel in `options`. Load a
    /// diffusion model first via
    /// `loadModel(RAModelLoadRequest(...))` with `category = .imageGeneration`.
    static func generateImage(
        _ options: RADiffusionGenerationOptions
    ) async throws -> RADiffusionResult {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()

        guard isDiffusionModelLoaded() else {
            throw SDKException(code: .notInitialized, message: "Diffusion model not loaded", category: .component)
        }

        return try await CppBridge.Diffusion.shared.generate(options)
    }

    /// Stream typed diffusion events for an image generation.
    ///
    /// Yields `.started` → terminal `.completed` (carrying the full
    /// `RADiffusionResult`) or `.error`. Intermediate per-step progress is not
    /// yet emitted (the native diffusion stream kickoff in commons is a
    /// documented stub); the generated image itself is genuine.
    static func generateImageStream(
        _ options: RADiffusionGenerationOptions
    ) async throws -> AsyncStream<RADiffusionStreamEvent> {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()

        guard isDiffusionModelLoaded() else {
            throw SDKException(code: .notInitialized, message: "Diffusion model not loaded", category: .component)
        }

        return await CppBridge.Diffusion.shared.generateStream(options)
    }

    /// Cancel the current (streaming) image generation.
    static func cancelImageGeneration() async {
        await CppBridge.Diffusion.shared.cancel()
    }

    /// Returns true if a diffusion model is loaded in the lifecycle under the
    /// `.imageGeneration` category (which collapses to `SDK_COMPONENT_DIFFUSION`
    /// in C++ commons).
    private static func isDiffusionModelLoaded() -> Bool {
        firstLoadedModelSnapshot(categories: [.imageGeneration]) != nil
    }
}
