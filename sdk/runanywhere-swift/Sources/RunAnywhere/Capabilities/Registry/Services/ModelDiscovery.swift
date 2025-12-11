import Foundation

/// Service responsible for discovering models from various sources
class ModelDiscovery {
    // Provider registration removed - no longer needed
    private let logger = SDKLogger(category: "ModelDiscovery")

    init() {
    }

    // Provider registration removed - no longer needed

    func discoverLocalModels() async -> [ModelInfo] {
        logger.info("Starting local model discovery...")
        var models: [ModelInfo] = []
        let modelExtensions = ["mlmodel", "mlmodelc", "mlpackage", "tflite", "onnx", "gguf", "ggml", "mlx", "pte", "safetensors"]

        let directories = getDefaultModelDirectories()
        logger.info("Searching in \(directories.count) directories for cached models")

        for directory in directories {
            logger.debug("Checking directory: \(directory.path)")
            // Search for model files recursively
            await searchForModelsRecursively(in: directory, modelExtensions: modelExtensions) { model in
                models.append(model)
            }
        }

        // Also check for models in app bundle
        if let bundleModels = discoverBundleModels() {
            logger.info("Found \(bundleModels.count) models in app bundle")
            models.append(contentsOf: bundleModels)
        }

        logger.info("Local model discovery completed. Found \(models.count) total models")
        for model in models {
            logger.debug("Discovered model: \(model.id) at \(model.localPath?.path ?? "unknown path")")
        }

        return models
    }

    private func searchForModelsRecursively(in directory: URL, modelExtensions: [String], onModelFound: (ModelInfo) async -> Void) async {
        guard FileOperationsUtilities.exists(at: directory) else {
            logger.debug("Directory does not exist: \(directory.path)")
            return
        }

        guard let enumerator = FileOperationsUtilities.enumerateDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            logger.warning("Failed to create enumerator for: \(directory.path)")
            return
        }

        while let fileURL = enumerator.nextObject() as? URL {
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

    private func detectModel(at url: URL) async -> ModelInfo? {
        // Skip hidden files and directories
        if url.lastPathComponent.hasPrefix(".") {
            return nil
        }

        // Detect format from file extension
        guard let format = detectFormatFromExtension(url.pathExtension) else {
            return nil
        }

        // Determine compatible frameworks
        let frameworks = detectCompatibleFrameworks(format: format)

        // Get file size
        let fileSize = FileOperationsUtilities.fileSize(at: url) ?? 0

        // Create model info
        let modelId = generateModelId(from: url)
        let modelName = generateModelName(from: url)

        // Determine category based on format and frameworks
        let category = ModelCategory.from(format: format, frameworks: frameworks)

        return ModelInfo(
            id: modelId,
            name: modelName,
            category: category,
            format: format,
            localPath: url,
            downloadSize: fileSize,
            memoryRequired: estimateMemoryUsage(fileSize: fileSize, format: format),
            compatibleFrameworks: frameworks,
            preferredFramework: frameworks.first,
            contextLength: category == .language ? 2048 : nil,
            supportsThinking: false,
            metadata: nil
        )
    }

    private func getDefaultModelDirectories() -> [URL] {
        var directories: [URL] = []

        do {
            // Add the base Models directory
            let modelsURL = try ModelPathUtils.getModelsDirectory()
            directories.append(modelsURL)

            // Add framework-specific subdirectories
            for framework in LLMFramework.allCases {
                let frameworkURL = try ModelPathUtils.getFrameworkDirectory(framework: framework)
                directories.append(frameworkURL)
            }
        } catch {
            logger.error("Failed to get default model directories: \(error)")
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

    private func detectCompatibleFrameworks(format: ModelFormat) -> [LLMFramework] {
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

    private func generateModelId(from url: URL) -> String {
        // Use centralized path utility to extract model ID
        if let modelId = ModelPathUtils.extractModelId(from: url) {
            logger.debug("Generated model ID from path structure: '\(modelId)' from path: \(url.path)")
            return modelId
        }

        // Fallback to filename-based ID for other cases
        let filename = url.deletingPathExtension().lastPathComponent
        logger.debug("Generated model ID from filename fallback: '\(filename)' from path: \(url.path)")
        return filename
    }

    private func generateModelName(from url: URL) -> String {
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

    private func detectFormatFromExtension(_ ext: String) -> ModelFormat? {
        switch ext.lowercased() {
        case "mlmodel": return .mlmodel
        case "mlmodelc": return .mlmodel
        case "mlpackage": return .mlpackage
        case "tflite": return .tflite
        case "onnx": return .onnx
        case "ort": return .ort
        case "gguf": return .gguf
        case "ggml": return .ggml
        case "mlx": return .mlx
        case "pte": return .pte
        case "safetensors": return .safetensors
        default: return nil
        }
    }
}
