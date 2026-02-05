//
//  RunAnywhere+Diffusion.swift
//  RunAnywhere SDK
//
//  Public API for diffusion (image generation) operations.
//  Calls C++ directly via CppBridge.Diffusion for all operations.
//

import CRACommons
import Foundation

// MARK: - Image Generation

public extension RunAnywhere {

    /// Generate an image from a text prompt
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

        // Get handle from CppBridge.Diffusion
        let handle = try await CppBridge.Diffusion.shared.getHandle()

        // Verify model is loaded
        guard await CppBridge.Diffusion.shared.isLoaded else {
            throw SDKError.diffusion(.notInitialized, "Diffusion model not loaded")
        }

        let opts = options ?? DiffusionGenerationOptions(prompt: prompt)

        // Build C options
        var cOptions = rac_diffusion_options_t()

        // Set basic options
        let result = prompt.withCString { promptPtr in
            cOptions.prompt = promptPtr

            return opts.negativePrompt.withCString { negPromptPtr -> rac_result_t in
                cOptions.negative_prompt = negPromptPtr
                cOptions.width = Int32(opts.width)
                cOptions.height = Int32(opts.height)
                cOptions.steps = Int32(opts.steps)
                cOptions.guidance_scale = opts.guidanceScale
                cOptions.seed = opts.seed
                cOptions.scheduler = opts.scheduler.cValue
                cOptions.mode = opts.mode.cValue
                cOptions.denoise_strength = opts.denoiseStrength
                cOptions.report_intermediate_images = opts.reportIntermediateImages ? RAC_TRUE : RAC_FALSE
                cOptions.progress_stride = Int32(opts.progressStride)

                // Handle input image for img2img/inpainting
                if let inputImage = opts.inputImage {
                    return inputImage.withUnsafeBytes { inputBytes -> rac_result_t in
                        cOptions.input_image_data = inputBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
                        cOptions.input_image_size = inputImage.count

                        // Handle mask for inpainting
                        if let maskImage = opts.maskImage {
                            return maskImage.withUnsafeBytes { maskBytes -> rac_result_t in
                                cOptions.mask_data = maskBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
                                cOptions.mask_size = maskImage.count

                                var diffusionResult = rac_diffusion_result_t()
                                let genResult = rac_diffusion_component_generate(handle, &cOptions, &diffusionResult)
                                return genResult
                            }
                        } else {
                            var diffusionResult = rac_diffusion_result_t()
                            return rac_diffusion_component_generate(handle, &cOptions, &diffusionResult)
                        }
                    }
                } else {
                    var diffusionResult = rac_diffusion_result_t()
                    return rac_diffusion_component_generate(handle, &cOptions, &diffusionResult)
                }
            }
        }

        // Re-generate to get the actual result (the above was just for building options)
        var finalResult = rac_diffusion_result_t()

        let generateResult = prompt.withCString { promptPtr in
            opts.negativePrompt.withCString { negPromptPtr -> rac_result_t in
                var genOptions = rac_diffusion_options_t()
                genOptions.prompt = promptPtr
                genOptions.negative_prompt = negPromptPtr
                genOptions.width = Int32(opts.width)
                genOptions.height = Int32(opts.height)
                genOptions.steps = Int32(opts.steps)
                genOptions.guidance_scale = opts.guidanceScale
                genOptions.seed = opts.seed
                genOptions.scheduler = opts.scheduler.cValue
                genOptions.mode = opts.mode.cValue
                genOptions.denoise_strength = opts.denoiseStrength
                genOptions.report_intermediate_images = RAC_FALSE
                genOptions.progress_stride = 1

                return rac_diffusion_component_generate(handle, &genOptions, &finalResult)
            }
        }

        guard generateResult == RAC_SUCCESS else {
            let errorMsg = finalResult.error_message.map { String(cString: $0) } ?? "Unknown error"
            rac_diffusion_result_free(&finalResult)
            throw SDKError.diffusion(.generationFailed, "Image generation failed: \(errorMsg)")
        }

        let swiftResult = DiffusionResult(from: finalResult)
        rac_diffusion_result_free(&finalResult)

        return swiftResult
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

        let handle = try await CppBridge.Diffusion.shared.getHandle()

        guard await CppBridge.Diffusion.shared.isLoaded else {
            throw SDKError.diffusion(.notInitialized, "Diffusion model not loaded")
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
                    let result = try await generateImageWithProgress(
                        handle: handle,
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

        let handle = try await CppBridge.Diffusion.shared.getHandle()

        guard await CppBridge.Diffusion.shared.isLoaded else {
            throw SDKError.diffusion(.notInitialized, "Diffusion model not loaded")
        }

        let opts = options ?? DiffusionGenerationOptions(prompt: prompt)

        return try await generateImageWithProgress(
            handle: handle,
            prompt: prompt,
            options: opts,
            onProgress: onProgress
        )
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

        // Configure if provided
        if let config = configuration {
            try await CppBridge.Diffusion.shared.configure(config)
        }

        // Load model
        try await CppBridge.Diffusion.shared.loadModel(modelPath, modelId: modelId, modelName: modelName)
    }

    /// Unload the current diffusion model
    static func unloadDiffusionModel() async throws {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        await CppBridge.Diffusion.shared.unload()
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
}

// MARK: - Private Helpers

private extension RunAnywhere {

    /// Internal helper for progress-based generation
    static func generateImageWithProgress(
        handle: rac_handle_t,
        prompt: String,
        options: DiffusionGenerationOptions,
        onProgress: @escaping (DiffusionProgress) -> Bool
    ) async throws -> DiffusionResult {

        // Create context for callbacks
        // Uses a flag to track whether callbacks have been invoked to prevent double-resume
        final class CallbackContext: @unchecked Sendable {
            var progressCallback: (DiffusionProgress) -> Bool
            var result: DiffusionResult?
            var error: Error?
            var completion: CheckedContinuation<DiffusionResult, Error>?
            var callbackInvoked = false  // Track if completion/error callback was called

            init(progressCallback: @escaping (DiffusionProgress) -> Bool) {
                self.progressCallback = progressCallback
            }
        }

        let context = CallbackContext(progressCallback: onProgress)

        return try await withCheckedThrowingContinuation { continuation in
            context.completion = continuation

            let contextPtr = Unmanaged.passRetained(context).toOpaque()

            // Progress callback
            let progressCallback: rac_diffusion_progress_callback_fn = { cProgressPtr, userData -> rac_bool_t in
                guard let cProgressPtr = cProgressPtr, let userData = userData else {
                    return RAC_TRUE
                }

                let ctx = Unmanaged<CallbackContext>.fromOpaque(userData).takeUnretainedValue()
                let progress = DiffusionProgress(from: cProgressPtr.pointee)

                let shouldContinue = ctx.progressCallback(progress)
                return shouldContinue ? RAC_TRUE : RAC_FALSE
            }

            // Complete callback - called by C++ on success
            let completeCallback: rac_diffusion_complete_callback_fn = { cResultPtr, userData in
                guard let cResultPtr = cResultPtr, let userData = userData else {
                    return
                }

                let ctx = Unmanaged<CallbackContext>.fromOpaque(userData).takeRetainedValue()
                ctx.callbackInvoked = true
                let result = DiffusionResult(from: cResultPtr.pointee)
                ctx.completion?.resume(returning: result)
            }

            // Error callback - called by C++ on failure (before returning error code)
            let errorCallback: rac_diffusion_error_callback_fn = { _, errorMessage, userData in
                guard let userData = userData else { return }

                let ctx = Unmanaged<CallbackContext>.fromOpaque(userData).takeRetainedValue()
                ctx.callbackInvoked = true
                let message = errorMessage.map { String(cString: $0) } ?? "Unknown error"
                let error = SDKError.diffusion(SDKError.DiffusionErrorCode.generationFailed, "Generation failed: \(message)")
                ctx.completion?.resume(throwing: error)
            }

            // Build C options and call
            prompt.withCString { promptPtr in
                options.negativePrompt.withCString { negPromptPtr in
                    var cOptions = rac_diffusion_options_t()
                    cOptions.prompt = promptPtr
                    cOptions.negative_prompt = negPromptPtr
                    cOptions.width = Int32(options.width)
                    cOptions.height = Int32(options.height)
                    cOptions.steps = Int32(options.steps)
                    cOptions.guidance_scale = options.guidanceScale
                    cOptions.seed = options.seed
                    cOptions.scheduler = options.scheduler.cValue
                    cOptions.mode = options.mode.cValue
                    cOptions.denoise_strength = options.denoiseStrength
                    cOptions.report_intermediate_images = options.reportIntermediateImages ? RAC_TRUE : RAC_FALSE
                    cOptions.progress_stride = Int32(options.progressStride)

                    let result = rac_diffusion_component_generate_with_callbacks(
                        handle,
                        &cOptions,
                        progressCallback,
                        completeCallback,
                        errorCallback,
                        contextPtr
                    )

                    // IMPORTANT: C++ code ALWAYS calls error_callback before returning failure,
                    // so we should NOT resume the continuation here - that would cause double-resume.
                    // The error_callback already released the context and resumed with error.
                    // We only handle the case where C++ returned failure WITHOUT calling error_callback
                    // (which shouldn't happen, but we check callbackInvoked for safety).
                    if result != RAC_SUCCESS {
                        // Check if callback was already invoked (context released)
                        // If so, do nothing - error_callback handled it
                        // If not (shouldn't happen), we need to clean up
                        let ctx = Unmanaged<CallbackContext>.fromOpaque(contextPtr).takeUnretainedValue()
                        if !ctx.callbackInvoked {
                            // Callback wasn't invoked, we need to release and resume
                            _ = Unmanaged<CallbackContext>.fromOpaque(contextPtr).takeRetainedValue()
                            let error = SDKError.diffusion(.generationFailed, "Failed to start generation: \(result)")
                            ctx.completion?.resume(throwing: error)
                        }
                        // If callbackInvoked is true, error_callback already handled everything
                    }
                }
            }
        }
    }
}
