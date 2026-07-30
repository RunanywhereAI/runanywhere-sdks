//
//  RunAnywhere+VisionLanguage.swift
//  RunAnywhere SDK
//
//  Deprecated flat VLM verbs. The v3 surface is `RunAnywhere.vlm`.
//

import CRACommons

// C struct with raw pointers — safe to send across concurrency boundaries
// because the backing Data (rgbData) is kept alive alongside it.
// `@retroactive` acknowledges we're extending a type imported from CRACommons.
extension rac_vlm_image_t: @retroactive @unchecked Sendable {}

public extension RunAnywhere {

    /// Process a generated-proto VLM image through the C++ VLM ABI.
    @available(*, deprecated, renamed: "vlm.generate(image:prompt:options:)")
    static func processImage(
        _ image: RAVLMImage,
        options: RAVLMGenerationOptions
    ) async throws -> RAVLMResult {
        try requireVLMModel()
        try await ensureServicesReady()
        return try await CppBridge.VLM.shared.process(image: image, options: options)
    }

    /// Stream typed VLM events from C++.
    @available(*, deprecated, renamed: "vlm.generateStream(image:prompt:options:)")
    static func processImageStream(
        _ image: RAVLMImage,
        options: RAVLMGenerationOptions
    ) async throws -> AsyncStream<RAVLMStreamEvent> {
        try requireVLMModel()
        try await ensureServicesReady()
        return try await CppBridge.VLM.shared.processStream(image: image, options: options)
    }

    /// Stream typed VLM events with the prompt applied onto `options`.
    @available(*, deprecated, renamed: "vlm.generateStream(image:prompt:options:)")
    static func processImageStream(
        _ image: RAVLMImage,
        prompt: String,
        options: RAVLMGenerationOptions = .defaults()
    ) async throws -> AsyncStream<RAVLMStreamEvent> {
        var effectiveOptions = options
        effectiveOptions.prompt = prompt
        try requireVLMModel()
        try await ensureServicesReady()
        return try await CppBridge.VLM.shared.processStream(image: image, options: effectiveOptions)
    }

    /// Cancel the current VLM generation.
    @available(*, deprecated, message: "Cancel the Task consuming vlm.generateStream instead")
    static func cancelVLMGeneration() async {
        await CppBridge.VLM.shared.cancel()
    }
}
