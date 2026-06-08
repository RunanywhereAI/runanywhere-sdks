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

    /// Stream generated-proto VLM events from C++.
    ///
    /// Phase 6j fixed the handle-type-mismatch root cause (`rac_vlm_component_t*`
    /// vs `rac_vlm_service_t*` cast in `rac_vlm_process_stream_proto`), so real
    /// per-token streaming works on both simulator and physical device. The
    /// synthesized single-event workaround has been removed.
    static func processImageStream(
        _ image: RAVLMImage,
        options: RAVLMGenerationOptions
    ) async throws -> AsyncStream<RASDKEvent> {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()

        guard isVLMModelLoaded() else {
            throw SDKException(code: .notInitialized, message: "VLM model not loaded", category: .component)
        }

        return try await CppBridge.VLM.shared.processStream(image: image, options: options)
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
