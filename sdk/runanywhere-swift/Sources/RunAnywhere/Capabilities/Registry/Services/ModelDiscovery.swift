import Foundation

/// Service responsible for discovering models from various sources
class ModelDiscovery {
    private let formatDetector: FormatDetector
    private let metadataExtractor: MetadataExtractor
    private var registeredProviders: [ModelProvider] = []
    private let logger = SDKLogger(category: "ModelDiscovery")

    init(
        formatDetector: FormatDetector = ServiceContainer.shared.formatDetector,
        metadataExtractor: MetadataExtractor = ServiceContainer.shared.metadataExtractor
    ) {
        self.formatDetector = formatDetector
        self.metadataExtractor = metadataExtractor
    }

    func registerProvider(_ provider: ModelProvider) {
        registeredProviders.append(provider)
    }

    func discoverLocalModels() async -> [ModelInfo] {
        var models: [ModelInfo] = []
        let modelExtensions = ["mlmodel", "mlmodelc", "mlpackage", "tflite", "onnx", "gguf", "ggml", "mlx", "pte", "safetensors"]

        for directory in getDefaultModelDirectories() {
            // Search for model files recursively
            await searchForModelsRecursively(in: directory, modelExtensions: modelExtensions) { model in
                models.append(model)
            }
        }

        // Also check for models in app bundle
        if let bundleModels = discoverBundleModels() {
            models.append(contentsOf: bundleModels)
        }

        return models
    }

    private func searchForModelsRecursively(in directory: URL, modelExtensions: [String], onModelFound: (ModelInfo) async -> Void) async {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            logger.debug("Directory does not exist: \(directory.path)")
            return
        }

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            logger.warning("Failed to create enumerator for: \(directory.path)")
            return
        }

        for case let fileURL as URL in enumerator {
            // Check if it's a file with a model extension
            let fileExtension = fileURL.pathExtension.lowercased()
            if modelExtensions.contains(fileExtension) {
                logger.debug("Found model file: \(fileURL.lastPathComponent)")
                if let model = await detectModel(at: fileURL) {
                    logger.info("Successfully detected model: \(model.name)")
                    await onModelFound(model)
                }
            }
        }
    }

    func discoverOnlineModels() async -> [ModelInfo] {
        var models: [ModelInfo] = []

        // Query each registered provider
        await withTaskGroup(of: [ModelInfo].self) { group in
            for provider in registeredProviders {
                group.addTask { [weak self] in
                    do {
                        return try await provider.listAvailableModels(limit: 100)
                    } catch {
                        self?.logger.error("Failed to query provider \(provider.name): \(error)")
                        return []
                    }
                }
            }

            for await providerModels in group {
                models.append(contentsOf: providerModels)
            }
        }

        return models
    }

    private func detectModel(at url: URL) async -> ModelInfo? {
        // Skip hidden files and directories
        if url.lastPathComponent.hasPrefix(".") {
            return nil
        }

        // Detect format
        guard let format = formatDetector.detectFormat(at: url) else {
            return nil
        }

        // Extract metadata
        let metadata: ModelMetadata
        do {
            metadata = await metadataExtractor.extractMetadata(from: url, format: format)
        } catch {
            // Create minimal metadata if extraction fails
            metadata = ModelMetadata(
                author: nil,
                description: url.deletingPathExtension().lastPathComponent,
                version: nil,
                modelType: nil,
                architecture: nil,
                quantization: nil,
                contextLength: nil,
                inputShapes: nil,
                outputShapes: nil
            )
        }

        // Determine compatible frameworks
        let frameworks = detectCompatibleFrameworks(format: format, metadata: metadata)

        // Get file size
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0

        // Create model info
        let modelId = generateModelId(from: url)
        let modelName = generateModelName(from: url, metadata: metadata)

        return ModelInfo(
            id: modelId,
            name: modelName,
            format: format,
            localPath: url,
            estimatedMemory: estimateMemoryUsage(fileSize: fileSize, format: format),
            contextLength: metadata.contextLength ?? 2048,
            downloadSize: fileSize,
            compatibleFrameworks: frameworks,
            preferredFramework: frameworks.first,
            hardwareRequirements: detectHardwareRequirements(format: format, metadata: metadata),
            tokenizerFormat: detectTokenizerFormat(at: url),
            metadata: convertToModelInfoMetadata(metadata)
        )
    }

    private func getDefaultModelDirectories() -> [URL] {
        var directories: [URL] = []

        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let modelsURL = documentsURL.appendingPathComponent("RunAnywhere", isDirectory: true).appendingPathComponent("Models", isDirectory: true)

            // Add the base Models directory
            directories.append(modelsURL)

            // Add framework-specific subdirectories
            for framework in LLMFramework.allCases {
                let frameworkURL = modelsURL.appendingPathComponent(framework.rawValue, isDirectory: true)
                directories.append(frameworkURL)
            }
        }

        return directories
    }

    private func discoverBundleModels() -> [ModelInfo]? {
        var models: [ModelInfo] = []

        let bundle = Bundle.main
        let modelExtensions = ["mlmodel", "mlmodelc", "mlpackage", "tflite", "onnx", "gguf"]

        for ext in modelExtensions {
            if let urls = bundle.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                for url in urls {
                    Task {
                        if let model = await detectModel(at: url) {
                            models.append(model)
                        }
                    }
                }
            }
        }

        return models.isEmpty ? nil : models
    }

    private func detectCompatibleFrameworks(format: ModelFormat, metadata: ModelMetadata) -> [LLMFramework] {
        var frameworks: [LLMFramework] = []

        switch format {
        case .mlmodel, .mlpackage:
            frameworks.append(.coreML)
        case .tflite:
            frameworks.append(.tensorFlowLite)
        case .onnx, .ort:
            frameworks.append(.onnx)
        case .safetensors:
            frameworks.append(.mlx)
        case .gguf, .ggml:
            frameworks.append(.llamaCpp)
        case .pte:
            frameworks.append(.execuTorch)
        default:
            break
        }

        return frameworks
    }

    private func detectHardwareRequirements(format: ModelFormat, metadata: ModelMetadata) -> [HardwareRequirement] {
        var requirements: [HardwareRequirement] = []

        if let minMemory = metadata.requirements?.minMemory {
            requirements.append(.minimumMemory(minMemory))
        }

        switch format {
        case .mlmodel, .mlpackage:
            requirements.append(.requiresNeuralEngine)
        case .tflite:
            requirements.append(.requiresGPU)
        case .safetensors:
            requirements.append(.specificChip("A17"))
        default:
            break
        }

        return requirements
    }

    private func detectTokenizerFormat(at url: URL) -> TokenizerFormat? {
        let directory = url.hasDirectoryPath ? url : url.deletingLastPathComponent()

        do {
            let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)

            for file in contents {
                let filename = file.lastPathComponent

                if filename == "tokenizer.json" {
                    return .huggingFace
                } else if filename.contains("sentencepiece") {
                    return .sentencePiece
                } else if filename == "vocab.txt" {
                    return .wordPiece
                } else if file.pathExtension == "bpe" {
                    return .bpe
                }
            }
        } catch {
            // Ignore errors
        }

        return nil
    }

    private func generateModelId(from url: URL) -> String {
        // For models in our storage structure, use the parent folder name as ID
        // This ensures consistency with how models are stored
        let pathComponents = url.pathComponents

        // Check if this is a model in our framework structure
        if let modelsIndex = pathComponents.firstIndex(of: "Models"),
           modelsIndex + 2 < pathComponents.count {
            // Path is like: .../Models/frameworkName/modelId/file.gguf
            // or: .../Models/modelId/file.gguf
            let nextComponent = pathComponents[modelsIndex + 1]

            // Check if next component is a framework name
            if LLMFramework.allCases.contains(where: { $0.rawValue == nextComponent }) {
                // Framework structure: use the model folder name
                if modelsIndex + 2 < pathComponents.count {
                    return pathComponents[modelsIndex + 2]
                }
            } else {
                // Direct model folder structure
                return nextComponent
            }
        }

        // Fallback to filename-based ID for other cases
        let filename = url.deletingPathExtension().lastPathComponent
        return filename
    }

    private func generateModelName(from url: URL, metadata: ModelMetadata) -> String {
        if let name = metadata.description {
            return name
        }

        return url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private func estimateMemoryUsage(fileSize: Int64, format: ModelFormat) -> Int64 {
        switch format {
        case .gguf, .ggml:
            return fileSize
        case .mlmodel, .mlpackage:
            return Int64(Double(fileSize) * 1.5)
        case .tflite:
            return fileSize
        case .safetensors:
            return Int64(Double(fileSize) * 1.2)
        default:
            return Int64(Double(fileSize) * 1.5)
        }
    }

    private func convertToModelInfoMetadata(_ metadata: ModelMetadata) -> ModelInfoMetadata {
        let quantLevel: QuantizationLevel? = {
            guard let q = metadata.quantization else { return nil }
            return QuantizationLevel(rawValue: q)
        }()

        return ModelInfoMetadata(
            author: metadata.author,
            license: nil,
            tags: [],
            description: metadata.description,
            trainingDataset: nil,
            baseModel: nil,
            quantizationLevel: quantLevel
        )
    }
}
