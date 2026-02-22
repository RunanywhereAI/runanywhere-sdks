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
    ///   - tokenizerSource: Source for downloading missing tokenizer files (defaults to SD 1.5)
    public func initialize(
        modelPath: String,
        reduceMemory: Bool = true,
        disableSafetyChecker: Bool = false,
        tokenizerSource: DiffusionTokenizerSource = .sd15
    ) async throws {
        logger.info("Initializing diffusion pipeline from: \(URL(fileURLWithPath: modelPath).lastPathComponent)")
        logger.info("Tokenizer source: \(tokenizerSource.description)")

        // Verify the directory exists
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw SDKError.diffusion(.modelNotFound, "Model directory not found: \(modelPath)")
        }

        // Find the actual model directory (handles nested directory structure from zip extraction)
        let resourceURL = try findModelResourceDirectory(at: URL(fileURLWithPath: modelPath))
        logger.info("Using model resources from: \(resourceURL.lastPathComponent)")

        // Ensure tokenizer files exist (Apple's compiled models don't include them)
        try await ensureTokenizerFiles(at: resourceURL, source: tokenizerSource)

        do {
            // Create pipeline configuration
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine

            logger.info("Creating StableDiffusionPipeline... (this may take a few minutes on first run)")

            // Create the pipeline
            pipeline = try StableDiffusionPipeline(
                resourcesAt: resourceURL,
                controlNet: [],
                configuration: config,
                disableSafety: disableSafetyChecker,
                reduceMemory: reduceMemory
            )

            logger.info("Pipeline created, loading resources... (Core ML model compilation in progress, please wait)")
            logger.info("⏳ First-time model compilation can take 5-15 minutes. Subsequent loads will be faster.")

            // Load resources - this triggers Core ML compilation on first run
            // WARNING: This can take 5-15 minutes on first run as Core ML compiles the model for the device's ANE
            try pipeline?.loadResources()

            self.modelPath = modelPath
            logger.info("✅ Diffusion pipeline initialized successfully")
        } catch {
            logger.error("❌ Failed to initialize pipeline: \(error)")
            throw SDKError.diffusion(.initializationFailed, "Failed to initialize: \(error.localizedDescription)")
        }
    }

    // MARK: - Model Directory Resolution

    /// Find the actual model resource directory, handling nested directory structures
    /// When a model zip is extracted with `nestedDirectory` structure, the CoreML files
    /// may be inside a subdirectory (e.g., `coreml-stable-diffusion-v1-5-palettized_split_einsum_v2_compiled/`)
    /// - Parameter baseURL: The base model directory URL
    /// - Returns: URL to the directory containing CoreML model files (Unet.mlmodelc, etc.)
    private func findModelResourceDirectory(at baseURL: URL) throws -> URL {
        let fileManager = FileManager.default

        // Check if Unet.mlmodelc exists directly in the base directory
        let directUnet = baseURL.appendingPathComponent("Unet.mlmodelc")
        if fileManager.fileExists(atPath: directUnet.path) {
            logger.debug("Found Unet.mlmodelc directly in model directory")
            return baseURL
        }

        // Look for a subdirectory containing Unet.mlmodelc (nested directory structure)
        do {
            let contents = try fileManager.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: [.isDirectoryKey])
            for item in contents {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    let nestedUnet = item.appendingPathComponent("Unet.mlmodelc")
                    if fileManager.fileExists(atPath: nestedUnet.path) {
                        logger.info("Found CoreML models in nested directory: \(item.lastPathComponent)")
                        return item
                    }
                }
            }
        } catch {
            logger.warning("Error scanning model directory: \(error.localizedDescription)")
        }

        // If we get here, we couldn't find the model files - return base URL and let the pipeline report the error
        logger.warning("Could not find Unet.mlmodelc in \(baseURL.lastPathComponent) or its subdirectories")
        return baseURL
    }

    // MARK: - Tokenizer Files

    /// Required tokenizer files for CLIP-based models
    private static let requiredTokenizerFiles = ["merges.txt", "vocab.json"]

    /// Ensure tokenizer files exist in the model directory
    /// Apple's compiled CoreML models don't include tokenizer files, so we download them if missing
    /// - Parameters:
    ///   - modelURL: The model directory URL
    ///   - source: The tokenizer source to use (defaults to SD 1.5)
    private func ensureTokenizerFiles(at modelURL: URL, source: DiffusionTokenizerSource = .sd15) async throws {
        let fileManager = FileManager.default

        for filename in Self.requiredTokenizerFiles {
            let fileURL = modelURL.appendingPathComponent(filename)

            if fileManager.fileExists(atPath: fileURL.path) {
                logger.debug("Tokenizer file exists: \(filename)")
                continue
            }

            logger.info("Downloading missing tokenizer file: \(filename) from \(source.description)")

            guard let remoteURL = URL(string: "\(source.baseURL)/\(filename)") else {
                throw SDKError.diffusion(.initializationFailed, "Invalid tokenizer URL for: \(filename)")
            }

            do {
                let (data, response) = try await URLSession.shared.data(from: remoteURL)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw SDKError.diffusion(.initializationFailed, "Failed to download \(filename): HTTP \(statusCode)")
                }

                try data.write(to: fileURL)
                logger.info("Downloaded tokenizer file: \(filename) (\(data.count) bytes)")
            } catch let error as SDKError {
                throw error
            } catch {
                throw SDKError.diffusion(.initializationFailed, "Failed to download \(filename): \(error.localizedDescription)")
            }
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
                // Flatten double optional: currentImages is [CGImage?], .first returns CGImage??
                let currentImage = progress.currentImages.first.flatMap { $0 }
                let progressInfo = DiffusionProgressInfo(
                    step: progress.step,
                    totalSteps: progress.stepCount,
                    progress: Float(progress.step) / Float(progress.stepCount),
                    currentImage: currentImage
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

// MARK: - SDKError Extension (uses DiffusionErrorCode from DiffusionTypes.swift)
