//
//  ImagesNamespace.swift
//  RunAnywhere SDK
//
//  `RunAnywhere.images` — diffusion. Inpainting is `ImageOptions.mode`, not a
//  separate verb.
//

import Foundation

public extension RunAnywhere {

    /// Image generation.
    static var images: Images { Images() }

    /// Paint images from a prompt.
    struct Images: Sendable {

        /// Generate an image for `prompt`.
        ///
        /// ```swift
        /// let result = try await RunAnywhere.images.generate(prompt: "a red bicycle")
        /// print(result.images.count)
        /// ```
        ///
        /// - Throws: `SDKException` when no diffusion model is loaded or generation fails.
        public func generate(
            prompt: String,
            options: ImageOptions? = nil
        ) async throws -> ImageResult {
            let effective = options ?? ImageOptions()
            let protoOptions = try effective.toProto(prompt: prompt)
            // DiffusionResult carries no error field on the unary path
            // (idl/diffusion_options.proto): failures travel out-of-band via
            // rac_proto_buffer_t status, which NativeProtoABI.invoke already
            // throws from inside generateImageProto.
            let result = try await RunAnywhere.generateImageProto(protoOptions)
            return ImageResult(proto: result, requestedSteps: effective.steps ?? Int(protoOptions.steps))
        }

        /// Generate an image, reporting step progress as it denoises.
        ///
        /// - Throws: `SDKException` from this call when no diffusion model is
        ///   loaded, and into the returned stream when generation fails.
        public func generateStream(
            prompt: String,
            options: ImageOptions? = nil
        ) async throws -> AsyncThrowingStream<ImageEvent, Error> {
            let effective = options ?? ImageOptions()
            let protoOptions = try effective.toProto(prompt: prompt)
            try RunAnywhere.requireDiffusionModel()
            try await RunAnywhere.ensureServicesReady()

            let events = await CppBridge.Diffusion.shared.generateStream(protoOptions)
            let steps = effective.steps ?? Int(protoOptions.steps)

            return AsyncThrowingStream { continuation in
                let task = Task {
                    var sawCompletion = false
                    for await event in events {
                        if Task.isCancelled { break }
                        switch event.kind {
                        case .started:
                            continuation.yield(.started)
                        case .progress, .intermediateImage:
                            // intermediateImageWidth/Height were deleted
                            // outright (idl/diffusion_options.proto);
                            // DiffusionProgress now only carries the raw
                            // bytes, with no resolved dimensions.
                            let progress = event.progress
                            let partial: ImageData? = progress.hasIntermediateImageData
                                ? ImageData(data: progress.intermediateImageData, width: 0, height: 0)
                                : nil
                            continuation.yield(.progress(
                                step: Int(progress.currentStep),
                                totalSteps: Int(progress.totalSteps),
                                partialImage: partial
                            ))
                        case .completed:
                            let result = event.hasResult ? event.result : RADiffusionResult()
                            continuation.yield(.completed(ImageResult(proto: result, requestedSteps: steps)))
                            sawCompletion = true
                        case .error:
                            continuation.finish(throwing: SDKException(proto: event.error))
                            return
                        default:
                            break
                        }
                    }

                    // No image can be synthesized from nothing, so a stream that
                    // ends without `completed` is a failure, not a quiet finish.
                    if !sawCompletion, !Task.isCancelled {
                        continuation.finish(throwing: SDKException(
                            code: .generationFailed,
                            message: "Image generation ended without producing an image",
                            category: .component
                        ))
                        return
                    }
                    continuation.finish()
                }
                continuation.onTermination = { @Sendable termination in
                    task.cancel()
                    if case .cancelled = termination {
                        Task { await CppBridge.Diffusion.shared.cancel() }
                    }
                }
            }
        }
    }
}

// MARK: - Internal proto-level helpers

extension RunAnywhere {

    internal static func requireDiffusionModel() throws {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        guard firstLoadedModelSnapshot(categories: [.imageGeneration]) != nil else {
            throw SDKException(code: .modelNotLoaded, message: "Diffusion model not loaded", category: .component)
        }
    }

    internal static func generateImageProto(
        _ options: RADiffusionGenerationOptions
    ) async throws -> RADiffusionResult {
        try requireDiffusionModel()
        try await ensureServicesReady()
        return try await CppBridge.Diffusion.shared.generate(options)
    }
}
