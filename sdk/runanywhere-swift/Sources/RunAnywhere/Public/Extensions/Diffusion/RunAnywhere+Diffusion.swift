//
//  RunAnywhere+Diffusion.swift
//  RunAnywhere SDK
//
//  Public API for diffusion (image generation) operations.
//  Routes to appropriate backend based on model framework:
//  - CoreML models (.coreml) → DiffusionPlatformService (ANE acceleration)
//  - ONNX models (.onnx) → CppBridge.Diffusion (C++ backend)
//

import CoreGraphics
import CRACommons
import Foundation
import StableDiffusion

// MARK: - Backend State Management

/// Tracks the currently loaded diffusion backend and framework
private actor DiffusionBackendState {
    static let shared = DiffusionBackendState()
    
    private var _loadedFramework: InferenceFramework?
    private var _coreMLService: DiffusionPlatformService?
    private var _currentModelPath: String?
    private var _currentModelId: String?
    private var _currentConfiguration: DiffusionConfiguration?
    
    var loadedFramework: InferenceFramework? { _loadedFramework }
    var coreMLService: DiffusionPlatformService? { _coreMLService }
    var currentModelPath: String? { _currentModelPath }
    var currentModelId: String? { _currentModelId }
    var currentConfiguration: DiffusionConfiguration? { _currentConfiguration }
    
    var isLoaded: Bool {
        get async {
            if _loadedFramework == .onnx {
                return true
            }
            if let service = _coreMLService {
                return await service.isReady
            }
            return false
        }
    }
    
    func setLoaded(
        framework: InferenceFramework,
        modelPath: String,
        modelId: String,
        configuration: DiffusionConfiguration?
    ) {
        _loadedFramework = framework
        _currentModelPath = modelPath
        _currentModelId = modelId
        _currentConfiguration = configuration
    }
    
    func setCoreMLService(_ service: DiffusionPlatformService) {
        _coreMLService = service
    }
    
    func unload() async {
        if let service = _coreMLService {
            await service.unload()
        }
        _coreMLService = nil
        _loadedFramework = nil
        _currentModelPath = nil
        _currentModelId = nil
        _currentConfiguration = nil
    }
}

// MARK: - Image Generation

public extension RunAnywhere {

    /// Generate an image from a text prompt
    ///
    /// Automatically routes to the appropriate backend based on the loaded model's framework:
    /// - CoreML models: Uses Apple's StableDiffusionPipeline with ANE acceleration (30-60s)
    /// - ONNX models: Uses C++ ONNX Runtime (CPU fallback, 2-5 min)
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

        // Check which framework is loaded
        guard let framework = await DiffusionBackendState.shared.loadedFramework else {
            throw SDKError.diffusion(.notInitialized, "No diffusion model loaded. Call loadDiffusionModel first.")
        }

        let opts = options ?? DiffusionGenerationOptions(prompt: prompt)

        // Route to appropriate backend based on framework
        switch framework {
        case .coreml:
            return try await generateImageWithCoreML(prompt: prompt, options: opts)
        case .onnx:
            return try await generateImageWithONNX(prompt: prompt, options: opts)
        default:
            throw SDKError.diffusion(.unsupportedBackend, "Unsupported framework: \(framework.rawValue)")
        }
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

        guard let framework = await DiffusionBackendState.shared.loadedFramework else {
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

        guard let framework = await DiffusionBackendState.shared.loadedFramework else {
            throw SDKError.diffusion(.notInitialized, "No diffusion model loaded")
        }

        let opts = options ?? DiffusionGenerationOptions(prompt: prompt)

        switch framework {
        case .coreml:
            return try await generateImageWithCoreMLProgress(prompt: prompt, options: opts, onProgress: onProgress)
        case .onnx:
            return try await generateImageWithONNXProgress(prompt: prompt, options: opts, onProgress: onProgress)
        default:
            throw SDKError.diffusion(.unsupportedBackend, "Unsupported framework: \(framework.rawValue)")
        }
    }

    /// Cancel ongoing image generation
    static func cancelImageGeneration() async throws {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        let framework = await DiffusionBackendState.shared.loadedFramework
        
        switch framework {
        case .coreml:
            await DiffusionBackendState.shared.coreMLService?.cancel()
        case .onnx:
            await CppBridge.Diffusion.shared.cancel()
        default:
            break
        }
    }

    /// Load a diffusion model
    ///
    /// Automatically detects the model framework based on directory contents:
    /// - CoreML: Contains .mlmodelc directories (Unet.mlmodelc, TextEncoder.mlmodelc, etc.)
    /// - ONNX: Contains .onnx files (unet/model.onnx, text_encoder/model.onnx, etc.)
    ///
    /// You can also explicitly specify the framework via `configuration.preferredFramework`.
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

        // Determine framework: explicit preference > auto-detection
        let framework = configuration?.preferredFramework ?? detectFramework(from: modelPath)
        
        SDKLogger.shared.info("[Diffusion] Loading model '\(modelId)' with framework: \(framework.rawValue)")
        SDKLogger.shared.info("[Diffusion] Model path: \(modelPath)")

        switch framework {
        case .coreml:
            try await loadDiffusionModelWithCoreML(
                modelPath: modelPath,
                modelId: modelId,
                configuration: configuration
            )
        case .onnx:
            try await loadDiffusionModelWithONNX(
                modelPath: modelPath,
                modelId: modelId,
                modelName: modelName,
                configuration: configuration
            )
        default:
            throw SDKError.diffusion(.unsupportedBackend, "Unsupported framework: \(framework.rawValue). Use .coreml or .onnx")
        }

        // Record the loaded state
        await DiffusionBackendState.shared.setLoaded(
            framework: framework,
            modelPath: modelPath,
            modelId: modelId,
            configuration: configuration
        )
        
        SDKLogger.shared.info("[Diffusion] Model '\(modelId)' loaded successfully with \(framework.rawValue) backend")
    }

    /// Unload the current diffusion model
    static func unloadDiffusionModel() async throws {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        let framework = await DiffusionBackendState.shared.loadedFramework
        
        switch framework {
        case .coreml:
            await DiffusionBackendState.shared.unload()
        case .onnx:
            await CppBridge.Diffusion.shared.unload()
            await DiffusionBackendState.shared.unload()
        default:
            await DiffusionBackendState.shared.unload()
        }
        
        SDKLogger.shared.info("[Diffusion] Model unloaded")
    }

    /// Check if a diffusion model is loaded
    static var isDiffusionModelLoaded: Bool {
        get async {
            return await DiffusionBackendState.shared.isLoaded
        }
    }

    /// Get the currently loaded diffusion model ID
    static var currentDiffusionModelId: String? {
        get async {
            return await DiffusionBackendState.shared.currentModelId
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
            return await DiffusionBackendState.shared.loadedFramework
        }
    }
}

// MARK: - Framework Detection

private extension RunAnywhere {

    /// Detect the model framework from the model directory contents
    ///
    /// Detection rules:
    /// - CoreML: Has .mlmodelc directories (compiled CoreML models)
    /// - ONNX: Has .onnx files in subdirectories
    ///
    /// - Parameter path: Path to the model directory
    /// - Returns: Detected InferenceFramework
    static func detectFramework(from path: String) -> InferenceFramework {
        let fm = FileManager.default
        
        // Check for CoreML models (.mlmodelc directories)
        // Common patterns for CoreML Stable Diffusion models
        let coreMLIndicators = [
            "Unet.mlmodelc",
            "TextEncoder.mlmodelc",
            "VAEDecoder.mlmodelc",
            "VAEEncoder.mlmodelc",
            "SafetyChecker.mlmodelc",
            "TextEncoder2.mlmodelc"  // SDXL
        ]
        
        for indicator in coreMLIndicators {
            let indicatorPath = (path as NSString).appendingPathComponent(indicator)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: indicatorPath, isDirectory: &isDir), isDir.boolValue {
                SDKLogger.shared.debug("[Diffusion] Detected CoreML model (found \(indicator))")
                return .coreml
            }
        }
        
        // Check for ONNX models (.onnx files)
        let onnxIndicators = [
            "unet/model.onnx",
            "text_encoder/model.onnx",
            "vae_decoder/model.onnx",
            "vae_encoder/model.onnx"
        ]
        
        for indicator in onnxIndicators {
            let indicatorPath = (path as NSString).appendingPathComponent(indicator)
            if fm.fileExists(atPath: indicatorPath) {
                SDKLogger.shared.debug("[Diffusion] Detected ONNX model (found \(indicator))")
                return .onnx
            }
        }
        
        // Default to ONNX if we can't determine
        SDKLogger.shared.warning("[Diffusion] Could not detect model framework, defaulting to ONNX")
        return .onnx
    }
}

// MARK: - CoreML Backend Implementation

private extension RunAnywhere {

    /// Load a diffusion model using CoreML (Apple Neural Engine)
    static func loadDiffusionModelWithCoreML(
        modelPath: String,
        modelId: String,
        configuration: DiffusionConfiguration?
    ) async throws {
        SDKLogger.shared.info("[Diffusion.CoreML] Loading CoreML model from: \(modelPath)")
        
        // Create or reuse the CoreML service
        let service = DiffusionPlatformService()
        
        // Configure the service
        let reduceMemory = configuration?.reduceMemory ?? true
        let tokenizerSource = configuration?.effectiveTokenizerSource ?? .sd15
        
        do {
            try await service.initialize(
                modelPath: modelPath,
                reduceMemory: reduceMemory,
                disableSafetyChecker: !(configuration?.enableSafetyChecker ?? true),
                tokenizerSource: tokenizerSource
            )
            
            await DiffusionBackendState.shared.setCoreMLService(service)
            
            SDKLogger.shared.info("[Diffusion.CoreML] CoreML model loaded successfully with ANE acceleration")
        } catch {
            SDKLogger.shared.error("[Diffusion.CoreML] Failed to load CoreML model: \(error)")
            throw SDKError.diffusion(.loadFailed, "Failed to load CoreML model: \(error.localizedDescription)")
        }
    }

    /// Generate an image using CoreML backend
    static func generateImageWithCoreML(
        prompt: String,
        options: DiffusionGenerationOptions
    ) async throws -> DiffusionResult {
        guard let service = await DiffusionBackendState.shared.coreMLService else {
            throw SDKError.diffusion(.notInitialized, "CoreML service not initialized")
        }
        
        let config = await DiffusionBackendState.shared.currentConfiguration
        let variant = config?.modelVariant ?? .sd15
        
        // Use model-specific defaults if not specified
        let steps = options.steps > 0 ? options.steps : variant.defaultSteps
        let guidanceScale = options.guidanceScale > 0 ? options.guidanceScale : variant.defaultGuidanceScale
        
        SDKLogger.shared.info("[Diffusion.CoreML] Generating image: \(options.width)x\(options.height), \(steps) steps, CFG=\(guidanceScale)")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let result = try await service.generate(
            prompt: prompt,
            negativePrompt: options.negativePrompt,
            width: options.width,
            height: options.height,
            stepCount: steps,
            guidanceScale: guidanceScale,
            seed: options.seed > 0 ? UInt32(options.seed) : nil,
            scheduler: options.scheduler.toAppleScheduler()
        )
        
        let elapsed = Int64((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        SDKLogger.shared.info("[Diffusion.CoreML] Generation completed in \(elapsed)ms")
        
        // Convert to SDK result
        guard let imageData = result.imageData else {
            if result.safetyTriggered {
                throw SDKError.diffusion(.safetyCheckerTriggered, "Image blocked by safety checker")
            }
            throw SDKError.diffusion(.generationFailed, "No image generated")
        }
        
        return DiffusionResult(
            imageData: imageData,
            width: result.width,
            height: result.height,
            seedUsed: result.seedUsed,
            generationTimeMs: elapsed,
            safetyFlagged: result.safetyTriggered
        )
    }

    /// Generate an image with progress using CoreML backend
    static func generateImageWithCoreMLProgress(
        prompt: String,
        options: DiffusionGenerationOptions,
        onProgress: @escaping (DiffusionProgress) -> Bool
    ) async throws -> DiffusionResult {
        guard let service = await DiffusionBackendState.shared.coreMLService else {
            throw SDKError.diffusion(.notInitialized, "CoreML service not initialized")
        }
        
        let config = await DiffusionBackendState.shared.currentConfiguration
        let variant = config?.modelVariant ?? .sd15
        
        let steps = options.steps > 0 ? options.steps : variant.defaultSteps
        let guidanceScale = options.guidanceScale > 0 ? options.guidanceScale : variant.defaultGuidanceScale
        
        SDKLogger.shared.info("[Diffusion.CoreML] Generating with progress: \(options.width)x\(options.height), \(steps) steps")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let result = try await service.generate(
            prompt: prompt,
            negativePrompt: options.negativePrompt,
            width: options.width,
            height: options.height,
            stepCount: steps,
            guidanceScale: guidanceScale,
            seed: options.seed > 0 ? UInt32(options.seed) : nil,
            scheduler: options.scheduler.toAppleScheduler(),
            progressHandler: { progressInfo in
                let progress = DiffusionProgress(
                    progress: progressInfo.progress,
                    currentStep: progressInfo.step,
                    totalSteps: progressInfo.totalSteps,
                    stage: "Generating",
                    intermediateImage: progressInfo.currentImage.flatMap { convertCGImageToData($0) }
                )
                return onProgress(progress)
            }
        )
        
        let elapsed = Int64((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        
        guard let imageData = result.imageData else {
            if result.safetyTriggered {
                throw SDKError.diffusion(.safetyCheckerTriggered, "Image blocked by safety checker")
            }
            throw SDKError.diffusion(.generationFailed, "No image generated")
        }
        
        return DiffusionResult(
            imageData: imageData,
            width: result.width,
            height: result.height,
            seedUsed: result.seedUsed,
            generationTimeMs: elapsed,
            safetyFlagged: result.safetyTriggered
        )
    }
    
    /// Convert CGImage to Data
    static func convertCGImageToData(_ image: CGImage) -> Data? {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow
        
        var data = Data(count: totalBytes)
        
        guard data.withUnsafeMutableBytes({ ptr -> Bool in
            guard let context = CGContext(
                data: ptr.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }) else {
            return nil
        }
        
        return data
    }
}

// MARK: - ONNX Backend Implementation

private extension RunAnywhere {

    /// Load a diffusion model using ONNX Runtime (C++ backend)
    static func loadDiffusionModelWithONNX(
        modelPath: String,
        modelId: String,
        modelName: String,
        configuration: DiffusionConfiguration?
    ) async throws {
        SDKLogger.shared.info("[Diffusion.ONNX] Loading ONNX model from: \(modelPath)")
        
        // Configure if provided
        if let config = configuration {
            try await CppBridge.Diffusion.shared.configure(config)
        }

        // Load model via C++ bridge
        try await CppBridge.Diffusion.shared.loadModel(modelPath, modelId: modelId, modelName: modelName)
        
        SDKLogger.shared.info("[Diffusion.ONNX] ONNX model loaded successfully")
    }

    /// Generate an image using ONNX backend (fixed - no double generation)
    static func generateImageWithONNX(
        prompt: String,
        options: DiffusionGenerationOptions
    ) async throws -> DiffusionResult {
        let handle = try await CppBridge.Diffusion.shared.getHandle()

        guard await CppBridge.Diffusion.shared.isLoaded else {
            throw SDKError.diffusion(.notInitialized, "ONNX model not loaded")
        }

        SDKLogger.shared.info("[Diffusion.ONNX] Generating image: \(options.width)x\(options.height), \(options.steps) steps")

        var finalResult = rac_diffusion_result_t()

        let generateResult = prompt.withCString { promptPtr in
            options.negativePrompt.withCString { negPromptPtr -> rac_result_t in
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
                cOptions.report_intermediate_images = RAC_FALSE
                cOptions.progress_stride = 1

                return rac_diffusion_component_generate(handle, &cOptions, &finalResult)
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

    /// Generate an image with progress using ONNX backend
    static func generateImageWithONNXProgress(
        prompt: String,
        options: DiffusionGenerationOptions,
        onProgress: @escaping (DiffusionProgress) -> Bool
    ) async throws -> DiffusionResult {
        let handle = try await CppBridge.Diffusion.shared.getHandle()

        guard await CppBridge.Diffusion.shared.isLoaded else {
            throw SDKError.diffusion(.notInitialized, "ONNX model not loaded")
        }

        // Create context for callbacks
        final class CallbackContext: @unchecked Sendable {
            var progressCallback: (DiffusionProgress) -> Bool
            var result: DiffusionResult?
            var error: Error?
            var completion: CheckedContinuation<DiffusionResult, Error>?
            var callbackInvoked = false

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

            // Complete callback
            let completeCallback: rac_diffusion_complete_callback_fn = { cResultPtr, userData in
                guard let cResultPtr = cResultPtr, let userData = userData else {
                    return
                }

                let ctx = Unmanaged<CallbackContext>.fromOpaque(userData).takeRetainedValue()
                ctx.callbackInvoked = true
                let result = DiffusionResult(from: cResultPtr.pointee)
                ctx.completion?.resume(returning: result)
            }

            // Error callback
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

                    if result != RAC_SUCCESS {
                        let ctx = Unmanaged<CallbackContext>.fromOpaque(contextPtr).takeUnretainedValue()
                        if !ctx.callbackInvoked {
                            _ = Unmanaged<CallbackContext>.fromOpaque(contextPtr).takeRetainedValue()
                            let error = SDKError.diffusion(.generationFailed, "Failed to start generation: \(result)")
                            ctx.completion?.resume(throwing: error)
                        }
                    }
                }
            }
        }
    }
}
