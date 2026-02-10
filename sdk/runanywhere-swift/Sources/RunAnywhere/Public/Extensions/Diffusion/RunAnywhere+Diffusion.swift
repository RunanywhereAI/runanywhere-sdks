//
//  RunAnywhere+Diffusion.swift
//  RunAnywhere SDK
//
//  Public API for diffusion (image generation) operations.
//  Uses Apple Stable Diffusion (CoreML) with ANE acceleration.
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
            if _loadedFramework == .coreml, let service = _coreMLService {
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

        // Check which framework is loaded
        guard let framework = await DiffusionBackendState.shared.loadedFramework else {
            throw SDKError.diffusion(.notInitialized, "No diffusion model loaded. Call loadDiffusionModel first.")
        }

        let opts = options ?? DiffusionGenerationOptions(prompt: prompt)

        guard framework == .coreml else {
            throw SDKError.diffusion(.unsupportedBackend, "Unsupported framework: \(framework.rawValue). Only CoreML is supported.")
        }

        return try await generateImageWithCoreML(prompt: prompt, options: opts)
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

        guard framework == .coreml else {
            throw SDKError.diffusion(.unsupportedBackend, "Unsupported framework: \(framework.rawValue). Only CoreML is supported.")
        }

        return try await generateImageWithCoreMLProgress(prompt: prompt, options: opts, onProgress: onProgress)
    }

    /// Cancel ongoing image generation
    static func cancelImageGeneration() async throws {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        await DiffusionBackendState.shared.coreMLService?.cancel()
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

        // Determine framework: explicit preference > auto-detection
        let framework = configuration?.preferredFramework ?? detectFramework(from: modelPath)
        
        SDKLogger.shared.info("[Diffusion] Loading model '\(modelId)' with framework: \(framework.rawValue)")
        SDKLogger.shared.info("[Diffusion] Model path: \(modelPath)")

        guard framework == .coreml else {
            throw SDKError.diffusion(.unsupportedBackend, "Unsupported framework: \(framework.rawValue). Only CoreML is supported.")
        }

        try await loadDiffusionModelWithCoreML(
            modelPath: modelPath,
            modelId: modelId,
            configuration: configuration
        )

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

    /// Detect the model framework from the model directory contents.
    /// Only Apple CoreML is supported; default to CoreML when unknown.
    static func detectFramework(from path: String) -> InferenceFramework {
        let fm = FileManager.default
        let coreMLIndicators = [
            "Unet.mlmodelc",
            "TextEncoder.mlmodelc",
            "VAEDecoder.mlmodelc",
            "VAEEncoder.mlmodelc",
            "SafetyChecker.mlmodelc",
            "TextEncoder2.mlmodelc"
        ]
        for indicator in coreMLIndicators {
            let indicatorPath = (path as NSString).appendingPathComponent(indicator)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: indicatorPath, isDirectory: &isDir), isDir.boolValue {
                SDKLogger.shared.debug("[Diffusion] Detected CoreML model (found \(indicator))")
                return .coreml
            }
        }
        SDKLogger.shared.warning("[Diffusion] Could not detect CoreML; defaulting to CoreML (Apple only)")
        return .coreml
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

