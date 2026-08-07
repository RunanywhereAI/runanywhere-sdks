//
//  RunAnywhere+Diffusion.swift
//  RunAnywhere SDK
//
//  Deprecated flat diffusion verbs. The v3 surface is `RunAnywhere.images`.
//

import CRACommons

public extension RunAnywhere {

    /// Generate an image from the lifecycle-loaded diffusion model.
    @available(*, deprecated, renamed: "images.generate(prompt:options:)")
    static func generateImage(
        _ options: RADiffusionGenerationOptions
    ) async throws -> RADiffusionResult {
        try await generateImageProto(options)
    }

    /// Stream typed diffusion events for an image generation.
    @available(*, deprecated, renamed: "images.generateStream(prompt:options:)")
    static func generateImageStream(
        _ options: RADiffusionGenerationOptions
    ) async throws -> AsyncStream<RADiffusionStreamEvent> {
        try requireDiffusionModel()
        try await ensureServicesReady()
        return await CppBridge.Diffusion.shared.generateStream(options)
    }

    /// Cancel the current (streaming) image generation.
    @available(*, deprecated, message: "Cancel the Task consuming images.generateStream instead")
    static func cancelImageGeneration() async {
        await CppBridge.Diffusion.shared.cancel()
    }
}
