import Foundation
import RunAnywhere
import os
import SwiftUI

// MARK: - Diffusion ViewModel

/// Minimal ViewModel for Image Generation
@MainActor
class DiffusionViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.runanywhere", category: "Diffusion")

    // MARK: - Published State

    @Published var isModelLoaded = false
    @Published var currentModelName: String?
    @Published var currentBackend: String = "" // "CoreML" or "ONNX"
    @Published var availableModels: [ModelInfo] = []
    @Published var selectedModel: ModelInfo?

    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadStatus: String = ""

    @Published var isGenerating = false
    @Published var progress: Float = 0.0
    @Published var statusMessage: String = "Ready"
    @Published var errorMessage: String?

    @Published var generatedImage: Image?
    @Published var prompt: String = "A serene mountain landscape at sunset with golden light"

    private var isInitialized = false

    static let samplePrompts = [
        "A serene mountain landscape at sunset with golden light",
        "A futuristic city with flying cars and neon lights",
        "A cute corgi puppy wearing a tiny astronaut helmet",
        "An ancient library filled with magical floating books",
        "A cozy coffee shop on a rainy day, warm lighting"
    ]

    // MARK: - Computed

    var canGenerate: Bool {
        !prompt.isEmpty && !isGenerating && isModelLoaded
    }

    // MARK: - Init

    func initialize() async {
        guard !isInitialized else { return }
        isInitialized = true
        await loadAvailableModels()
        await checkModelState()
    }

    // MARK: - Models

    func loadAvailableModels() async {
        do {
            let allModels = try await RunAnywhere.availableModels()
            availableModels = allModels.filter {
                $0.category == ModelCategory.imageGeneration && !$0.isBuiltIn && $0.artifactType.requiresDownload
            }
            if let downloaded = availableModels.first(where: { $0.isDownloaded }) {
                selectedModel = downloaded
            } else if let first = availableModels.first {
                selectedModel = first
            }
        } catch {
            logger.error("Failed to load models: \(error.localizedDescription)")
        }
    }

    func checkModelState() async {
        do {
            isModelLoaded = try await RunAnywhere.isDiffusionModelLoaded
            if isModelLoaded {
                currentModelName = try await RunAnywhere.currentDiffusionModelId
                // Determine backend from selected model
                if let model = selectedModel {
                    currentBackend = model.framework.displayName
                }
            }
        } catch {
            logger.error("Failed to check model state: \(error.localizedDescription)")
        }
    }

    func downloadModel(_ model: ModelInfo) async {
        guard !isDownloading, !model.isBuiltIn else { return }

        isDownloading = true
        downloadProgress = 0.0
        downloadStatus = "Starting..."
        errorMessage = nil

        do {
            let stream = try await RunAnywhere.downloadModel(model.id)
            for await progress in stream {
                downloadProgress = progress.overallProgress
                downloadStatus = "Downloading: \(Int(progress.overallProgress * 100))%"
                if progress.stage == .completed { break }
            }
            await loadAvailableModels()
            selectedModel = availableModels.first { $0.id == model.id }
        } catch {
            errorMessage = "Download failed: \(error.localizedDescription)"
        }

        isDownloading = false
    }

    /// Detect model variant from model ID
    private func detectModelVariant(from modelId: String) -> DiffusionModelVariant {
        let lowerId = modelId.lowercased()
        if lowerId.contains("sdxs") {
            return .sdxs  // Ultra-fast 1-step
        } else if lowerId.contains("lcm") {
            return .lcm   // Fast 4-step
        } else if lowerId.contains("turbo") {
            return .sdxlTurbo  // Fast 4-step
        } else if lowerId.contains("sdxl") || lowerId.contains("xl") {
            return .sdxl
        } else if lowerId.contains("sd21") || lowerId.contains("2.1") || lowerId.contains("2-1") {
            return .sd21
        }
        return .sd15  // Default
    }
    
    @Published var currentModelVariant: DiffusionModelVariant = .sd15
    
    func loadSelectedModel() async {
        guard let model = selectedModel, model.isDownloaded, let path = model.localPath else {
            errorMessage = "Model not downloaded"
            return
        }

        statusMessage = "Loading model..."
        errorMessage = nil

        do {
            // Detect model variant to apply correct defaults
            let variant = detectModelVariant(from: model.id)
            currentModelVariant = variant
            
            let config = DiffusionConfiguration(modelVariant: variant, enableSafetyChecker: true, reduceMemory: true)
            try await RunAnywhere.loadDiffusionModel(modelPath: path.path, modelId: model.id, modelName: model.name, configuration: config)
            isModelLoaded = true
            currentModelName = model.name
            currentBackend = model.framework.displayName
            
            // Show helpful info about the model
            let stepsInfo = variant.defaultSteps == 1 ? "1 step (ultra-fast)" : "\(variant.defaultSteps) steps"
            statusMessage = "Model loaded (\(currentBackend), \(stepsInfo))"
            logger.info("Loaded \(model.name) as \(variant.rawValue) - \(stepsInfo)")
        } catch {
            errorMessage = "Load failed: \(error.localizedDescription)"
            statusMessage = "Failed"
        }
    }

    // MARK: - Generation

    func generateImage() async {
        guard canGenerate else {
            errorMessage = "Enter a prompt"
            return
        }

        isGenerating = true
        progress = 0.0
        statusMessage = "Generating..."
        errorMessage = nil
        generatedImage = nil

        do {
            // Use model variant defaults for optimal performance
            // - SDXS: 512x512, 1 step, no CFG (ultra-fast ~2-10 sec)
            // - LCM: 512x512, 4 steps, low CFG (fast ~15-30 sec)  
            // - SD 1.5/Turbo: defaults based on variant
            let variant = self.currentModelVariant
            let resolution = variant.defaultResolution
            let steps = variant.defaultSteps
            let guidanceScale = variant.defaultGuidanceScale
            
            // For mobile, cap resolution to avoid memory issues
            let maxMobileRes = 512
            let width = min(resolution.width, maxMobileRes)
            let height = min(resolution.height, maxMobileRes)
            
            logger.info("Generating with \(variant.rawValue): \(width)x\(height), \(steps) steps, CFG=\(guidanceScale)")
            
            let options = DiffusionGenerationOptions(
                prompt: prompt,
                width: width,
                height: height,
                steps: steps,
                guidanceScale: guidanceScale
            )
            let stream = try await RunAnywhere.generateImageStream(prompt: prompt, options: options)

            for try await update in stream {
                progress = update.progress
                if steps == 1 {
                    statusMessage = "Processing (1-step model)..."
                } else {
                    statusMessage = "Step \(update.currentStep)/\(update.totalSteps)"
                }
            }

            let result = try await RunAnywhere.generateImage(prompt: prompt, options: options)
            if let uiImage = createImage(from: result.imageData, width: result.width, height: result.height) {
                generatedImage = Image(uiImage: uiImage)
                statusMessage = "Done in \(result.generationTimeMs)ms"
            } else {
                errorMessage = "Failed to create image"
            }
        } catch {
            errorMessage = "Generation failed: \(error.localizedDescription)"
            statusMessage = "Failed"
        }

        isGenerating = false
    }

    func cancelGeneration() async {
        try? await RunAnywhere.cancelImageGeneration()
        statusMessage = "Cancelled"
        isGenerating = false
    }

    // MARK: - Helpers

    #if os(iOS)
    private func createImage(from data: Data, width: Int, height: Int) -> UIImage? {
        let size = width * height * 4
        guard data.count >= size else { return nil }

        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                  width: width, height: height,
                  bitsPerComponent: 8, bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider, decode: nil,
                  shouldInterpolate: true, intent: .defaultIntent
              ) else { return nil }

        return UIImage(cgImage: cgImage)
    }
    #elseif os(macOS)
    private func createImage(from data: Data, width: Int, height: Int) -> NSImage? {
        let size = width * height * 4
        guard data.count >= size else { return nil }

        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                  width: width, height: height,
                  bitsPerComponent: 8, bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider, decode: nil,
                  shouldInterpolate: true, intent: .defaultIntent
              ) else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
    #endif
}
