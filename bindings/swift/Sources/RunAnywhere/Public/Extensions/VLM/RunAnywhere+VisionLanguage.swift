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

    /// Process a generated-proto VLM request through the C++ VLM ABI.
    ///
    /// `RAVLMGenerationOptions` was deleted outright (idl/vlm_options.proto);
    /// this forwarder's parameter necessarily changes from the deleted
    /// options type to the full `RAVLMGenerationRequest` envelope
    /// (images/messages/prompt/options/vision) that replaced it.
    @available(*, deprecated, renamed: "vlm.generate(image:prompt:options:)")
    static func processImage(
        _ request: RAVLMGenerationRequest
    ) async throws -> RAVLMResult {
        try requireVLMModel()
        try await ensureServicesReady()
        return try await CppBridge.VLM.shared.process(request)
    }

    /// Stream typed VLM events from C++.
    @available(*, deprecated, renamed: "vlm.generateStream(image:prompt:options:)")
    static func processImageStream(
        _ request: RAVLMGenerationRequest
    ) async throws -> AsyncStream<RAVLMStreamEvent> {
        try requireVLMModel()
        try await ensureServicesReady()
        return try await CppBridge.VLM.shared.processStream(request)
    }

    /// Stream typed VLM events for one image + prompt, using default sampling.
    @available(*, deprecated, renamed: "vlm.generateStream(image:prompt:options:)")
    static func processImageStream(
        _ image: RAVLMImage,
        prompt: String,
        options: RALLMGenerationOptions = .defaults()
    ) async throws -> AsyncStream<RAVLMStreamEvent> {
        var request = RAVLMGenerationRequest()
        request.images = [image]
        request.prompt = prompt
        request.options = options
        try requireVLMModel()
        try await ensureServicesReady()
        return try await CppBridge.VLM.shared.processStream(request)
    }

    /// Cancel the current VLM generation.
    @available(*, deprecated, message: "Cancel the Task consuming vlm.generateStream instead")
    static func cancelVLMGeneration() async {
        await CppBridge.VLM.shared.cancel()
    }
}
