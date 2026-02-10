//
//  RunAnywhere+Diffusion.swift
//  RunAnywhere SDK
//
//  Public API for diffusion (image generation) operations.
//  Routes through C++ component layer for architectural consistency with LLM/STT/TTS.
//  Uses Apple Stable Diffusion (CoreML) with ANE acceleration via platform callbacks.
//

import CRACommons
import Foundation

// MARK: - Image Generation

public extension RunAnywhere {

    /// Generate an image from a text prompt
    ///
    /// Uses Apple Stable Diffusion (CoreML) with ANE acceleration when a model is loaded.
    ///
    /// Example usage:
    /// ```swift
    /// let result = try await RunAnywhere.generateImage(prompt: "A sunset over mountains")
    /// let image = UIImage(data: result.imageData)
    /// ```
    ///
    /// - Parameters:
    ///   - prompt: Text description of the desired image
    ///   - options: Generation options (optional, uses defaults if not provided)
    /// - Returns: DiffusionResult containing the generated image
    static func generateImage(
        prompt: String,
        options: DiffusionGenerationOptions? = nil
    ) async throws -> DiffusionResult {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()

        guard await CppBridge.Diffusion.shared.isLoaded else {
            throw SDKError.diffusion(.notInitialized, "No diffusion model loaded. Call loadDiffusionModel first.")
        }

        let opts = options ?? DiffusionGenerationOptions(prompt: prompt)
        return try await CppBridge.Diffusion.shared.generate(options: opts)
    }

    /// Generate an image with progress reporting
    ///
    /// Example usage:
    /// ```swift
    /// let stream = try await RunAnywhere.generateImageStream(prompt: "A sunset")
    /// for try await progress in stream {
    ///     print("Step \(progress.currentStep)/\(progress.totalSteps)")
    ///     if let intermediate = progress.intermediateImage {
    ///         // Display intermediate image
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - prompt: Text description of the desired image
    ///   - options: Generation options
    /// - Returns: AsyncThrowingStream of DiffusionProgress updates
    static func generateImageStream(
        prompt: String,
        options: DiffusionGenerationOptions? = nil
    ) async throws -> AsyncThrowingStream<DiffusionProgress, Error> {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()

        guard await CppBridge.Diffusion.shared.isLoaded else {
            throw SDKError.diffusion(.notInitialized, "No diffusion model loaded")
        }

        var opts = options ?? DiffusionGenerationOptions(prompt: prompt)
        // Enable intermediate images for streaming
        opts = DiffusionGenerationOptions(
            prompt: opts.prompt,
            negativePrompt: opts.negativePrompt,
            width: opts.width,
            height: opts.height,
            steps: opts.steps,
            guidanceScale: opts.guidanceScale,
            seed: opts.seed,
            scheduler: opts.scheduler,
            mode: opts.mode,
            inputImage: opts.inputImage,
            maskImage: opts.maskImage,
            denoiseStrength: opts.denoiseStrength,
            reportIntermediateImages: true,
            progressStride: opts.progressStride > 0 ? opts.progressStride : 1
        )

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let result = try await generateImage(
                        prompt: prompt,
                        options: opts,
                        onProgress: { progress in
                            continuation.yield(progress)
                            return true // Continue generation
                        }
                    )

                    // Yield final progress
                    let finalProgress = DiffusionProgress(
                        progress: 1.0,
                        currentStep: opts.steps,
                        totalSteps: opts.steps,
                        stage: "Complete",
                        intermediateImage: result.imageData
                    )
                    continuation.yield(finalProgress)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Generate an image with a progress callback
    ///
    /// - Parameters:
    ///   - prompt: Text description of the desired image
    ///   - options: Generation options
    ///   - onProgress: Callback for progress updates, return false to cancel
    /// - Returns: DiffusionResult containing the generated image
    static func generateImage(
        prompt: String,
        options: DiffusionGenerationOptions? = nil,
        onProgress: @escaping (DiffusionProgress) -> Bool
    ) async throws -> DiffusionResult {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()

        guard await CppBridge.Diffusion.shared.isLoaded else {
            throw SDKError.diffusion(.notInitialized, "No diffusion model loaded")
        }

        let opts = options ?? DiffusionGenerationOptions(prompt: prompt)
        return try await CppBridge.Diffusion.shared.generateWithProgress(options: opts, onProgress: onProgress)
    }

    /// Cancel ongoing image generation
    static func cancelImageGeneration() async throws {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        await CppBridge.Diffusion.shared.cancel()
    }

    /// Load a diffusion model
    ///
    /// Expects a CoreML model directory containing .mlmodelc files
    /// (Unet.mlmodelc, TextEncoder.mlmodelc, etc.).
    ///
    /// You can explicitly specify the framework via `configuration.preferredFramework`.
    ///
    /// - Parameters:
    ///   - modelPath: Path to the model directory
    ///   - modelId: Model identifier
    ///   - modelName: Human-readable model name
    ///   - configuration: Optional configuration for the model
    static func loadDiffusionModel(
        modelPath: String,
        modelId: String,
        modelName: String,
        configuration: DiffusionConfiguration? = nil
    ) async throws {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()

        SDKLogger.shared.info("[Diffusion] Loading model '\(modelId)' via C++ component layer")
        SDKLogger.shared.info("[Diffusion] Model path: \(modelPath)")

        // Configure the component if configuration is provided
        if let config = configuration {
            try await CppBridge.Diffusion.shared.configure(config)
        }

        // Load via C++ component -> vtable dispatch -> platform callback -> DiffusionPlatformService
        try await CppBridge.Diffusion.shared.loadModel(modelPath, modelId: modelId, modelName: modelName)

        SDKLogger.shared.info("[Diffusion] Model '\(modelId)' loaded successfully via C++ component layer")
    }

    /// Unload the current diffusion model
    static func unloadDiffusionModel() async throws {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        await CppBridge.Diffusion.shared.unload()
        SDKLogger.shared.info("[Diffusion] Model unloaded")
    }

    /// Check if a diffusion model is loaded
    static var isDiffusionModelLoaded: Bool {
        get async {
            return await CppBridge.Diffusion.shared.isLoaded
        }
    }

    /// Get the currently loaded diffusion model ID
    static var currentDiffusionModelId: String? {
        get async {
            return await CppBridge.Diffusion.shared.currentModelId
        }
    }

    /// Get diffusion service capabilities
    static func getDiffusionCapabilities() async throws -> DiffusionCapabilities {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        return await CppBridge.Diffusion.shared.getCapabilities()
    }

    /// Get the currently loaded framework
    static var currentDiffusionFramework: InferenceFramework? {
        get async {
            // Always CoreML on Apple platforms
            guard await CppBridge.Diffusion.shared.isLoaded else { return nil }
            return .coreml
        }
    }
}
