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

    func loadSelectedModel() async {
        guard let model = selectedModel, model.isDownloaded, let path = model.localPath else {
            errorMessage = "Model not downloaded"
            return
        }

        statusMessage = "Loading model..."
        errorMessage = nil

        do {
            let config = DiffusionConfiguration(modelVariant: .sd15, enableSafetyChecker: true, reduceMemory: true)
            try await RunAnywhere.loadDiffusionModel(modelPath: path.path, modelId: model.id, modelName: model.name, configuration: config)
            isModelLoaded = true
            currentModelName = model.name
            currentBackend = model.framework.displayName
            statusMessage = "Model loaded (\(currentBackend))"
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
            let options = DiffusionGenerationOptions(prompt: prompt)
            let stream = try await RunAnywhere.generateImageStream(prompt: prompt, options: options)

            for try await update in stream {
                progress = update.progress
                statusMessage = "Step \(update.currentStep)/\(update.totalSteps)"
            }

            let result = try await RunAnywhere.generateImage(prompt: prompt, options: options)
            if let uiImage = createImage(from: result.imageData, width: result.width, height: result.height) {
                generatedImage = Image(uiImage: uiImage)
                statusMessage = "Done"
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
