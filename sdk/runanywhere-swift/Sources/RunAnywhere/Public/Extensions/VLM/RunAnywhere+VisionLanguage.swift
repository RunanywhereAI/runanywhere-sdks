//
//  RunAnywhere+VisionLanguage.swift
//  RunAnywhere SDK
//
//  Public API for Vision Language Model (VLM) operations.
//  Uses C++ directly via CppBridge.VLM.
//
//  Loading flows through the canonical lifecycle (`RAModelLoadRequest`).
//  This file owns only inference (image processing) entry points.
//

import CRACommons

// C struct with raw pointers — safe to send across concurrency boundaries
// because the backing Data (rgbData) is kept alive alongside it.
// `@retroactive` acknowledges we're extending a type imported from CRACommons.
extension rac_vlm_image_t: @retroactive @unchecked Sendable {}

// MARK: - Vision Language Model

public extension RunAnywhere {

    /// Process a generated-proto VLM image through the C++ VLM ABI.
    static func processImage(
        _ image: RAVLMImage,
        options: RAVLMGenerationOptions
    ) async throws -> RAVLMResult {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()

        // Query ModelLifecycle (the canonical source of truth) instead of
        // the CppBridge.VLM actor's per-handle state. VLM accepts both
        // `.multimodal` and `.vision` — try `.multimodal` first (the
        // canonical category used by SDK consumers and example apps), fall
        // back to `.vision` so models loaded under either category are
        // honored. Both collapse to `SDK_COMPONENT_VLM` in C++ commons.
        guard isVLMModelLoaded() else {
            throw SDKException(code: .notInitialized, message: "VLM model not loaded", category: .component)
        }

        return try await CppBridge.VLM.shared.process(image: image, options: options)
    }

    /// Stream typed VLM events from C++.
    ///
    /// Canonical cross-SDK shape: yields generated `RAVLMStreamEvent`s
    /// (STARTED → TOKEN* → exactly one terminal COMPLETED/ERROR; COMPLETED
    /// carries the full `RAVLMResult` with metrics). The prompt travels in
    /// `options.prompt`. Backed by `rac_vlm_stream_proto`, the same typed
    /// ABI Flutter and React Native consume.
    static func processImageStream(
        _ image: RAVLMImage,
        options: RAVLMGenerationOptions
    ) async throws -> AsyncStream<RAVLMStreamEvent> {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()

        guard isVLMModelLoaded() else {
            throw SDKException(code: .notInitialized, message: "VLM model not loaded", category: .component)
        }

        return try await CppBridge.VLM.shared.processStream(image: image, options: options)
    }

    /// Ergonomic overload mirroring React Native: the prompt is applied onto
    /// `options.prompt` before streaming.
    static func processImageStream(
        _ image: RAVLMImage,
        prompt: String,
        options: RAVLMGenerationOptions = .defaults()
    ) async throws -> AsyncStream<RAVLMStreamEvent> {
        var effectiveOptions = options
        effectiveOptions.prompt = prompt
        return try await processImageStream(image, options: effectiveOptions)
    }

    /// Returns true if a VLM model is loaded in the lifecycle under either
    /// the `.multimodal` or `.vision` category. Both categories collapse to
    /// `SDK_COMPONENT_VLM` in C++ commons.
    private static func isVLMModelLoaded() -> Bool {
        firstLoadedModelSnapshot(categories: [.multimodal, .vision]) != nil
    }

    /// Cancel the current VLM generation.
    static func cancelVLMGeneration() async {
        await CppBridge.VLM.shared.cancel()
    }
}
