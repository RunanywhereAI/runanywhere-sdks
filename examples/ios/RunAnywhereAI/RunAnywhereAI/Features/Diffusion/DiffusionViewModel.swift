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
    @Published var currentBackend: String = ""
    @Published var availableModels: [RAModelInfo] = []
    @Published var selectedModel: RAModelInfo?

    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadStatus: String = ""

    @Published var isLoadingModel = false

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
        let listResult = await RunAnywhere.listModels()
        guard listResult.success else {
            logger.error("Failed to load models: \(listResult.errorMessage)")
            return
        }
        availableModels = listResult.models.models.filter {
            $0.category == ModelCategory.imageGeneration && !$0.isBuiltIn && $0.artifactType.requiresDownload
        }
        if let downloaded = availableModels.first(where: { $0.isDownloaded }) {
            selectedModel = downloaded
        } else if let first = availableModels.first {
            selectedModel = first
        }
    }

    func checkModelState() async {
        isModelLoaded = await RunAnywhere.isDiffusionModelLoaded
        if isModelLoaded {
            currentModelName = await RunAnywhere.currentDiffusionModelId
            // Determine backend from selected model
            if let model = selectedModel {
                currentBackend = model.framework.displayName
            }
        }
    }

    func downloadModel(_ model: RAModelInfo) async {
        guard !isDownloading, !model.isBuiltIn else { return }

        isDownloading = true
        downloadProgress = 0.0
        downloadStatus = "Starting..."
        errorMessage = nil

        do {
            try await RunAnywhere.downloadModel(model) { progress in
                await MainActor.run {
                    self.downloadProgress = Double(progress.overallProgress)
                    self.downloadStatus = "\(progress.stage.displayName): \(Int(Double(progress.overallProgress) * 100))%"
                }
            }
            await loadAvailableModels()
            selectedModel = availableModels.first { $0.id == model.id }
        } catch {
            errorMessage = "Download failed: \(error.localizedDescription)"
        }

        isDownloading = false
    }

    @Published var currentModelVariant: RADiffusionModelVariant = .sd15

    func loadSelectedModel() async {
        guard let model = selectedModel, model.isDownloaded else {
            errorMessage = "Model not downloaded"
            return
        }

        isLoadingModel = true
        statusMessage = "Loading model..."
        errorMessage = nil

        defer { isLoadingModel = false }

        do {
            // Use SD 1.5 defaults unless the registry adds variant-specific metadata.
            let variant: RADiffusionModelVariant = .sd15
            currentModelVariant = variant

            var config = RADiffusionConfiguration.defaults()
            config.modelVariant = variant
            config.enableSafetyChecker = true
            config.reduceMemory = true
            try await RunAnywhere.loadDiffusionModel(model, configuration: config)
            isModelLoaded = true
            currentModelName = model.name
            currentBackend = model.framework.displayName

            // Show helpful info about the model
            let defaultSteps = self.defaultInferenceSteps(for: variant)
            let stepsInfo = defaultSteps == 1 ? "1 step (ultra-fast)" : "\(defaultSteps) steps"
            statusMessage = "Model loaded (\(currentBackend), \(stepsInfo))"
            logger.info("Loaded \(model.name) as \(self.displayName(for: variant)) - \(stepsInfo)")
        } catch {
            errorMessage = "Load failed: \(error.localizedDescription)"
            statusMessage = "Failed"
        }
    }

    // MARK: - Generation

    // swiftlint:disable:next function_body_length
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
            let resolution = self.defaultResolution(for: variant)
            let steps = self.defaultInferenceSteps(for: variant)
            let guidanceScale = self.defaultGuidanceScale(for: variant)

            // For mobile, cap resolution to avoid memory issues
            let maxMobileRes = 512
            let width = min(resolution.width, maxMobileRes)
            let height = min(resolution.height, maxMobileRes)

            logger.info("Generating with \(self.displayName(for: variant)): \(width)x\(height), \(steps) steps, CFG=\(guidanceScale)")

            var options = RADiffusionGenerationOptions.defaults(prompt: prompt)
            options.width = Int32(width)
            options.height = Int32(height)
            options.numInferenceSteps = steps
            options.guidanceScale = guidanceScale
            // Use the progress-callback overload so the pipeline runs only once.
            let result = try await RunAnywhere.generateImage(
                prompt: prompt,
                options: options
            ) { [weak self] update in
                Task { @MainActor [weak self] in
                    self?.progress = update.progressPercent
                    if steps == 1 {
                        self?.statusMessage = "Processing (1-step model)..."
                    } else {
                        self?.statusMessage = "Step \(update.currentStep)/\(update.totalSteps)"
                    }
                }
                return true // continue generation
            }
            if let platformImage = createImage(
                from: result.imageData,
                width: Int(result.width),
                height: Int(result.height)
            ) {
                #if os(iOS)
                generatedImage = Image(uiImage: platformImage)
                #elseif os(macOS)
                generatedImage = Image(nsImage: platformImage)
                #endif
                statusMessage = "Done in \(result.totalTimeMs)ms"
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
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              ) else { return nil }

        return UIImage(cgImage: cgImage)
    }
    #elseif os(macOS)
    private func createImage(from data: Data, width: Int, height: Int) -> NSImage? {
        let size = width * height * 4
        guard data.count >= size else { return nil }

        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              ) else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
    #endif

    private func defaultResolution(for variant: RADiffusionModelVariant) -> (width: Int, height: Int) {
        switch variant {
        case .sdxl, .sdxlTurbo:
            return (1024, 1024)
        case .sd21:
            return (768, 768)
        default:
            return (512, 512)
        }
    }

    private func defaultInferenceSteps(for variant: RADiffusionModelVariant) -> Int32 {
        switch variant {
        case .sdxs:
            return 1
        case .sdxlTurbo, .lcm:
            return 4
        case .sd21:
            return 28
        default:
            return 20
        }
    }

    private func defaultGuidanceScale(for variant: RADiffusionModelVariant) -> Float {
        switch variant {
        case .sdxs, .sdxlTurbo:
            return 0.0
        case .lcm:
            return 1.5
        default:
            return 7.5
        }
    }

    private func displayName(for variant: RADiffusionModelVariant) -> String {
        switch variant {
        case .sd15:
            return "SD 1.5"
        case .sd21:
            return "SD 2.1"
        case .sdxl:
            return "SDXL"
        case .sdxlTurbo:
            return "SDXL Turbo"
        case .sdxs:
            return "SDXS"
        case .lcm:
            return "LCM"
        default:
            return "Diffusion"
        }
    }
}
