import Foundation
import RunAnywhere
import Combine
import os
import SwiftUI

// MARK: - Diffusion ViewModel

/// ViewModel for Image Generation (Diffusion) functionality
///
/// Uses the RunAnywhere Diffusion API for text-to-image generation with Core ML.
@MainActor
class DiffusionViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.runanywhere", category: "Diffusion")

    // MARK: - Published Properties

    // Model State
    @Published var isModelLoaded = false
    @Published var currentModelId: String?
    @Published var currentModelName: String?

    // Available Models
    @Published var availableModels: [ModelInfo] = []
    @Published var selectedModel: ModelInfo?

    // Download State
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadStatus: String = ""

    // Generation State
    @Published var isGenerating = false
    @Published var progress: Float = 0.0
    @Published var currentStep: Int = 0
    @Published var totalSteps: Int = 0
    @Published var statusMessage: String = "Ready"
    @Published var errorMessage: String?

    // Generated Image
    @Published var generatedImage: Image?
    @Published var lastSeedUsed: Int64?

    // Generation Settings
    @Published var prompt: String = ""
    @Published var negativePrompt: String = "blurry, bad quality, distorted"
    @Published var width: Int = 512
    @Published var height: Int = 512
    @Published var steps: Int = 20
    @Published var guidanceScale: Float = 7.5
    @Published var seed: Int64 = -1 // -1 for random

    // Available options
    let availableResolutions: [(width: Int, height: Int, label: String)] = [
        (512, 512, "512x512 (SD 1.5)"),
        (768, 768, "768x768"),
        (512, 768, "512x768 (Portrait)"),
        (768, 512, "768x512 (Landscape)")
    ]

    let availableSteps: [Int] = [10, 15, 20, 25, 30, 40, 50]

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private var isInitialized = false

    // MARK: - Computed Properties

    var canGenerate: Bool {
        !prompt.isEmpty && !isGenerating && isModelLoaded
    }

    var hasDownloadedModels: Bool {
        availableModels.contains { $0.isDownloaded }
    }

    var progressPercentage: String {
        String(format: "%.0f%%", progress * 100)
    }

    // MARK: - Initialization

    /// Initialize the Diffusion view model
    func initialize() async {
        guard !isInitialized else {
            logger.debug("Diffusion view model already initialized, skipping")
            return
        }
        isInitialized = true

        logger.info("Initializing Diffusion view model")

        // Load available diffusion models
        await loadAvailableModels()

        // Check if diffusion model is already loaded
        await checkModelState()
    }

    // MARK: - Model Discovery

    /// Load available diffusion models from registry
    func loadAvailableModels() async {
        do {
            let allModels = try await RunAnywhere.availableModels()
            // Filter to image generation models that are not built-in (built-in models don't need downloading)
            // Built-in models like "coreml-diffusion" are placeholders and shouldn't appear in the list
            availableModels = allModels.filter {
                $0.category == ModelCategory.imageGeneration &&
                !$0.isBuiltIn &&
                $0.artifactType.requiresDownload
            }
            logger.info("Found \(self.availableModels.count) diffusion model(s)")

            // Auto-select first downloaded model, or first model if none downloaded
            if let downloaded = availableModels.first(where: { $0.isDownloaded }) {
                selectedModel = downloaded
            } else if let first = availableModels.first {
                selectedModel = first
            }
        } catch {
            logger.error("Failed to load available models: \(error.localizedDescription)")
        }
    }

    // MARK: - Model Management

    /// Check current model state
    func checkModelState() async {
        do {
            isModelLoaded = try await RunAnywhere.isDiffusionModelLoaded
            if isModelLoaded {
                currentModelId = try await RunAnywhere.currentDiffusionModelId
                currentModelName = currentModelId
                logger.info("Diffusion model already loaded: \(self.currentModelId ?? "unknown")")
            }
        } catch {
            logger.error("Failed to check diffusion model state: \(error.localizedDescription)")
        }
    }

    /// Download a diffusion model
    func downloadModel(_ model: ModelInfo) async {
        guard !isDownloading else { return }

        // Don't try to download built-in models
        guard !model.isBuiltIn && model.artifactType.requiresDownload else {
            logger.warning("Attempted to download built-in model: \(model.name)")
            errorMessage = "This model doesn't require downloading"
            return
        }

        logger.info("Starting download for: \(model.name)")
        isDownloading = true
        downloadProgress = 0.0
        downloadStatus = "Starting download..."
        errorMessage = nil

        do {
            let progressStream = try await RunAnywhere.downloadModel(model.id)

            for await progress in progressStream {
                self.downloadProgress = progress.overallProgress
                self.downloadStatus = "Downloading: \(Int(progress.overallProgress * 100))%"

                if progress.stage == .completed {
                    self.downloadStatus = "Download complete!"
                    logger.info("Download completed for: \(model.name)")
                    break
                }
            }

            // Reload models to update downloaded status
            await loadAvailableModels()
            selectedModel = availableModels.first { $0.id == model.id }

        } catch {
            logger.error("Download failed: \(error.localizedDescription)")
            errorMessage = "Download failed: \(error.localizedDescription)"
            downloadStatus = "Download failed"
        }

        isDownloading = false
    }

    /// Load the selected model
    func loadSelectedModel() async {
        guard let model = selectedModel else {
            errorMessage = "No model selected"
            return
        }

        guard model.isDownloaded, let localPath = model.localPath else {
            errorMessage = "Model not downloaded. Please download first."
            return
        }

        await loadModel(modelPath: localPath.path, modelId: model.id, modelName: model.name)
    }

    /// Load a diffusion model
    /// Note: First-time loading can take 5-15 minutes as Core ML compiles the model for the device's Neural Engine.
    /// Subsequent loads will be much faster.
    func loadModel(modelPath: String, modelId: String, modelName: String) async {
        logger.info("Loading diffusion model: \(modelName)")
        statusMessage = "Loading model... (first load may take 5-15 minutes for Core ML compilation)"
        errorMessage = nil

        do {
            // Configure the diffusion model
            // tokenizerSource defaults to the model variant's tokenizer (SD 1.5 in this case)
            // For custom fine-tuned models, you can specify a custom tokenizer:
            // tokenizerSource: .custom(baseURL: "https://huggingface.co/your-org/your-model/resolve/main/tokenizer")
            let config = DiffusionConfiguration(
                modelVariant: .sd15,
                enableSafetyChecker: true,
                reduceMemory: true,
                tokenizerSource: nil  // Uses default SD 1.5 tokenizer
            )

            try await RunAnywhere.loadDiffusionModel(
                modelPath: modelPath,
                modelId: modelId,
                modelName: modelName,
                configuration: config
            )

            isModelLoaded = true
            currentModelId = modelId
            currentModelName = modelName
            statusMessage = "Model loaded"
            logger.info("Diffusion model loaded successfully")
        } catch {
            logger.error("Failed to load diffusion model: \(error.localizedDescription)")
            errorMessage = "Failed to load model: \(error.localizedDescription)"
            statusMessage = "Load failed"
        }
    }

    /// Unload current model
    func unloadModel() async {
        logger.info("Unloading diffusion model")
        do {
            try await RunAnywhere.unloadDiffusionModel()
            isModelLoaded = false
            currentModelId = nil
            currentModelName = nil
            statusMessage = "Model unloaded"
        } catch {
            logger.error("Failed to unload diffusion model: \(error.localizedDescription)")
            errorMessage = "Failed to unload: \(error.localizedDescription)"
        }
    }

    // MARK: - Image Generation

    /// Generate an image from the current prompt and settings
    func generateImage() async {
        guard canGenerate else {
            errorMessage = "Enter a prompt to generate an image"
            return
        }

        logger.info("Generating image for prompt: \(self.prompt.prefix(50))...")
        isGenerating = true
        progress = 0.0
        currentStep = 0
        statusMessage = "Starting generation..."
        errorMessage = nil
        generatedImage = nil

        do {
            let options = DiffusionGenerationOptions(
                prompt: prompt,
                negativePrompt: negativePrompt,
                width: width,
                height: height,
                steps: steps,
                guidanceScale: guidanceScale,
                seed: seed
            )

            // Use streaming API for progress updates
            let stream = try await RunAnywhere.generateImageStream(
                prompt: prompt,
                options: options
            )

            for try await progressUpdate in stream {
                self.progress = progressUpdate.progress
                self.currentStep = progressUpdate.currentStep
                self.totalSteps = progressUpdate.totalSteps
                self.statusMessage = "Step \(progressUpdate.currentStep)/\(progressUpdate.totalSteps)"

                // If we have an intermediate image, show it
                if let imageData = progressUpdate.intermediateImage {
                    if let uiImage = createImage(from: imageData, width: width, height: height) {
                        self.generatedImage = Image(uiImage: uiImage)
                    }
                }
            }

            // After stream completes, get final result
            let result = try await RunAnywhere.generateImage(prompt: prompt, options: options)
            lastSeedUsed = result.seedUsed

            let imageData = result.imageData
            if let uiImage = createImage(from: imageData, width: result.width, height: result.height) {
                generatedImage = Image(uiImage: uiImage)
                statusMessage = "Generation complete"
                logger.info("Image generated successfully, seed: \(result.seedUsed)")
            } else {
                errorMessage = "Failed to create image from data"
                statusMessage = "Failed"
            }

        } catch {
            logger.error("Image generation failed: \(error.localizedDescription)")
            errorMessage = "Generation failed: \(error.localizedDescription)"
            statusMessage = "Failed"
        }

        isGenerating = false
    }

    /// Cancel ongoing generation
    func cancelGeneration() async {
        logger.info("Cancelling image generation")
        do {
            try await RunAnywhere.cancelImageGeneration()
            statusMessage = "Cancelled"
        } catch {
            logger.error("Failed to cancel: \(error.localizedDescription)")
        }
        isGenerating = false
    }

    // MARK: - Image Helpers

    #if os(iOS)
    private func createImage(from data: Data, width: Int, height: Int) -> UIImage? {
        // Assuming RGBA data
        let bytesPerPixel = 4
        let expectedSize = width * height * bytesPerPixel

        guard data.count >= expectedSize else {
            logger.error("Image data size mismatch: expected \(expectedSize), got \(data.count)")
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * bytesPerPixel,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
    #elseif os(macOS)
    private func createImage(from data: Data, width: Int, height: Int) -> NSImage? {
        let bytesPerPixel = 4
        let expectedSize = width * height * bytesPerPixel

        guard data.count >= expectedSize else {
            logger.error("Image data size mismatch: expected \(expectedSize), got \(data.count)")
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * bytesPerPixel,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
    #endif

    // MARK: - Cleanup

    func cleanup() {
        cancellables.removeAll()
        isInitialized = false
    }

    // MARK: - Preset Prompts

    static let samplePrompts = [
        "A serene mountain landscape at sunset with golden light",
        "A futuristic city with flying cars and neon lights",
        "A cute corgi puppy wearing a tiny astronaut helmet",
        "An ancient library filled with magical floating books",
        "A cozy coffee shop on a rainy day, warm lighting"
    ]
}

// MARK: - Platform Image Extension
// Note: SwiftUI already provides Image(uiImage:) on iOS and Image(nsImage:) on macOS
// No custom extensions needed - use the built-in initializers directly
