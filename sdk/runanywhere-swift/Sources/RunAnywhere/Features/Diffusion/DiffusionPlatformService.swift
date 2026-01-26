//
//  DiffusionPlatformService.swift
//  RunAnywhere SDK
//
//  Platform service for Core ML-based Stable Diffusion image generation.
//  Wraps Apple's ml-stable-diffusion StableDiffusionPipeline.
//

import CoreGraphics
import CoreML
import Foundation
import StableDiffusion

// MARK: - Diffusion Platform Service

/// Service that wraps Apple's ml-stable-diffusion StableDiffusionPipeline
/// for on-device image generation using Core ML.
@available(iOS 16.2, macOS 13.1, *)
public actor DiffusionPlatformService {

    // MARK: - Properties

    private let logger = SDKLogger(category: "DiffusionPlatformService")

    /// The underlying Stable Diffusion pipeline
    private var pipeline: StableDiffusionPipeline?

    /// Current model path
    private var modelPath: String?

    /// Whether the pipeline is ready
    public var isReady: Bool {
        pipeline != nil
    }

    /// Cancellation flag
    private var isCancelled = false

    // MARK: - Initialization

    public init() {}

    // MARK: - Lifecycle

    /// Initialize the pipeline with a model directory
    /// - Parameters:
    ///   - modelPath: Path to the directory containing Core ML model files
    ///   - reduceMemory: Whether to use reduced memory mode (recommended for iOS)
    ///   - disableSafetyChecker: Whether to disable the safety checker
    public func initialize(
        modelPath: String,
        reduceMemory: Bool = true,
        disableSafetyChecker: Bool = false
    ) async throws {
        logger.info("Initializing diffusion pipeline from: \(modelPath)")

        let resourceURL = URL(fileURLWithPath: modelPath)

        // Verify the directory exists
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw SDKError.diffusion(.modelNotFound, "Model directory not found: \(modelPath)")
        }

        do {
            // Create pipeline configuration
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine

            // Create the pipeline
            pipeline = try StableDiffusionPipeline(
                resourcesAt: resourceURL,
                controlNet: [],
                configuration: config,
                disableSafety: disableSafetyChecker,
                reduceMemory: reduceMemory
            )

            // Load resources
            try pipeline?.loadResources()

            self.modelPath = modelPath
            logger.info("Diffusion pipeline initialized successfully")
        } catch {
            logger.error("Failed to initialize pipeline: \(error)")
            throw SDKError.diffusion(.initializationFailed, "Failed to initialize: \(error.localizedDescription)")
        }
    }

    /// Unload the pipeline and free resources
    public func unload() {
        logger.info("Unloading diffusion pipeline")
        pipeline?.unloadResources()
        pipeline = nil
        modelPath = nil
    }

    // MARK: - Image Generation

    /// Generate images from a text prompt
    /// - Parameters:
    ///   - prompt: The text prompt describing the desired image
    ///   - negativePrompt: Text describing what to avoid in the image
    ///   - stepCount: Number of inference steps (default: 20)
    ///   - guidanceScale: How closely to follow the prompt (default: 7.5)
    ///   - seed: Random seed for reproducibility (nil for random)
    ///   - progressHandler: Callback for progress updates
    /// - Returns: Array of generated CGImages (may be nil if safety check triggered)
    public func generate(
        prompt: String,
        negativePrompt: String = "",
        width: Int = 512,
        height: Int = 512,
        stepCount: Int = 20,
        guidanceScale: Float = 7.5,
        seed: UInt32? = nil,
        scheduler: StableDiffusionScheduler = .dpmSolverMultistepScheduler,
        progressHandler: ((DiffusionProgressInfo) -> Bool)? = nil
    ) async throws -> DiffusionGenerationResult {
        guard let pipeline = pipeline else {
            throw SDKError.diffusion(.notInitialized, "Pipeline not initialized")
        }

        isCancelled = false
        let actualSeed = seed ?? UInt32.random(in: 0...UInt32.max)

        logger.info("Generating image - prompt: \(prompt.prefix(50))..., steps: \(stepCount), seed: \(actualSeed)")

        // Create configuration
        var config = StableDiffusionPipeline.Configuration(prompt: prompt)
        config.negativePrompt = negativePrompt
        config.stepCount = stepCount
        config.guidanceScale = guidanceScale
        config.seed = actualSeed
        config.schedulerType = scheduler
        config.disableSafety = false

        var lastProgress: DiffusionProgressInfo?

        do {
            let images = try pipeline.generateImages(configuration: config) { progress in
                // Check for cancellation
                if self.isCancelled {
                    return false
                }

                // Create progress info
                let progressInfo = DiffusionProgressInfo(
                    step: progress.step,
                    totalSteps: progress.stepCount,
                    progress: Float(progress.step) / Float(progress.stepCount),
                    currentImage: progress.currentImages.first ?? nil
                )
                lastProgress = progressInfo

                // Call handler if provided
                if let handler = progressHandler {
                    return handler(progressInfo)
                }
                return true
            }

            // Check if cancelled
            if isCancelled {
                throw SDKError.diffusion(.cancelled, "Generation was cancelled")
            }

            // Get the first image
            guard let cgImage = images.first else {
                throw SDKError.diffusion(.generationFailed, "No image generated")
            }

            // Check if image was filtered by safety checker
            let safetyTriggered = cgImage == nil

            // Convert to RGBA data
            var imageData: Data?
            var imageWidth = width
            var imageHeight = height

            if let image = cgImage {
                imageWidth = image.width
                imageHeight = image.height
                imageData = try convertToRGBAData(image)
            }

            logger.info("Image generated successfully - \(imageWidth)x\(imageHeight), safety: \(safetyTriggered)")

            return DiffusionGenerationResult(
                imageData: imageData,
                width: imageWidth,
                height: imageHeight,
                seedUsed: Int64(actualSeed),
                safetyTriggered: safetyTriggered
            )

        } catch let error as SDKError {
            throw error
        } catch {
            logger.error("Generation failed: \(error)")
            throw SDKError.diffusion(.generationFailed, error.localizedDescription)
        }
    }

    /// Cancel ongoing generation
    public func cancel() {
        logger.info("Cancelling generation")
        isCancelled = true
    }

    // MARK: - Image Conversion

    /// Convert a CGImage to RGBA data
    private func convertToRGBAData(_ image: CGImage) throws -> Data {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow

        var data = Data(count: totalBytes)

        try data.withUnsafeMutableBytes { ptr in
            guard let context = CGContext(
                data: ptr.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw SDKError.diffusion(.generationFailed, "Failed to create graphics context")
            }

            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        return data
    }
}

// MARK: - Supporting Types

/// Progress information for diffusion generation
public struct DiffusionProgressInfo: Sendable {
    /// Current step number
    public let step: Int

    /// Total number of steps
    public let totalSteps: Int

    /// Progress as a fraction (0.0 - 1.0)
    public let progress: Float

    /// Current intermediate image (if available)
    public let currentImage: CGImage?

    public init(step: Int, totalSteps: Int, progress: Float, currentImage: CGImage? = nil) {
        self.step = step
        self.totalSteps = totalSteps
        self.progress = progress
        self.currentImage = currentImage
    }
}

/// Result of diffusion generation
public struct DiffusionGenerationResult: Sendable {
    /// Generated image data in RGBA format
    public let imageData: Data?

    /// Image width
    public let width: Int

    /// Image height
    public let height: Int

    /// The seed that was used for generation
    public let seedUsed: Int64

    /// Whether the safety checker was triggered
    public let safetyTriggered: Bool

    public init(
        imageData: Data?,
        width: Int,
        height: Int,
        seedUsed: Int64,
        safetyTriggered: Bool
    ) {
        self.imageData = imageData
        self.width = width
        self.height = height
        self.seedUsed = seedUsed
        self.safetyTriggered = safetyTriggered
    }
}

// MARK: - SDKError Extension

extension SDKError {
    /// Diffusion-specific errors
    public enum DiffusionErrorCode: String, Sendable {
        case notInitialized = "DIFFUSION_NOT_INITIALIZED"
        case modelNotFound = "DIFFUSION_MODEL_NOT_FOUND"
        case initializationFailed = "DIFFUSION_INIT_FAILED"
        case generationFailed = "DIFFUSION_GENERATION_FAILED"
        case cancelled = "DIFFUSION_CANCELLED"
    }

    /// Create a diffusion error
    public static func diffusion(_ code: DiffusionErrorCode, _ message: String) -> SDKError {
        return SDKError.operationFailed(message)
    }
}
