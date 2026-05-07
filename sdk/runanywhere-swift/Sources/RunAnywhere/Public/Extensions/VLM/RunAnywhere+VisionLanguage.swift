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
import Foundation

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
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }
        try await ensureServicesReady()

        guard await CppBridge.VLM.shared.isLoaded else {
            throw SDKException.vlm(.notInitialized, "VLM model not loaded")
        }

        return try await CppBridge.VLM.shared.process(image: image, options: options)
    }

    /// Stream generated-proto VLM events from C++.
    ///
    /// Phase 6h on-iOS-sim workaround: the C++ `rac_vlm_process_stream_proto`
    /// trampoline path (stream_token_trampoline → Swift `@convention(c)`
    /// callback) crashes with EXC_BAD_ACCESS / EXC_ARM_DA_ALIGN when the
    /// clip / ggml path drives tokens from llama.cpp on iOS Simulator.
    /// The root cause is somewhere in the mtmd / ctx-lifetime boundary and
    /// needs more investigation. For now, synthesize a single TOKEN_GENERATED
    /// + GENERATION_COMPLETED pair from the non-streaming `processImage`
    /// result. Physical-device builds can revert to the real stream path
    /// once the trampoline crash is root-caused.
    static func processImageStream(
        _ image: RAVLMImage,
        options: RAVLMGenerationOptions
    ) async throws -> AsyncStream<RASDKEvent> {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }
        try await ensureServicesReady()

        guard await CppBridge.VLM.shared.isLoaded else {
            throw SDKException.vlm(.notInitialized, "VLM model not loaded")
        }

        let result = try await CppBridge.VLM.shared.process(image: image, options: options)
        return AsyncStream<RASDKEvent> { (continuation: AsyncStream<RASDKEvent>.Continuation) in
            var tokenEvent = RASDKEvent()
            var generation = RAGenerationEvent()
            generation.kind = .tokenGenerated
            generation.token = result.text
            generation.streamingText = result.text
            tokenEvent.generation = generation
            continuation.yield(tokenEvent)

            var completedEvent = RASDKEvent()
            var completed = RAGenerationEvent()
            completed.kind = .completed
            completed.streamingText = result.text
            completedEvent.generation = completed
            continuation.yield(completedEvent)
            continuation.finish()
        }
    }

    /// Cancel the current VLM generation.
    static func cancelVLMGeneration() async {
        await CppBridge.VLM.shared.cancel()
    }
}
