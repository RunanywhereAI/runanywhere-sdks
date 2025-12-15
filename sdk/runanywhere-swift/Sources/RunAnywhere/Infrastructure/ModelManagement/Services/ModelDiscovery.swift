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

        // Discover models in framework-specific directories (directory-based models)
        let frameworkModels = await discoverFrameworkModels()
        models.append(contentsOf: frameworkModels)

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

    /// Discover models by checking model folders within framework directories
    /// This approach respects directory-based models (ONNX, WhisperKit, etc.)
    /// instead of finding individual files which creates duplicate entries
    @MainActor
    private func discoverFrameworkModels() async -> [ModelInfo] {
        var models: [ModelInfo] = []

        guard let modelsURL = try? ModelPathUtils.getModelsDirectory() else {
            logger.error("Failed to get models directory")
            return []
        }

        let fm = FileManager.default
        guard let frameworkFolders = try? fm.contentsOfDirectory(at: modelsURL, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }

        for frameworkFolder in frameworkFolders {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: frameworkFolder.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            // Check if this is a known framework folder
            guard let framework = InferenceFramework.allCases.first(where: { $0.rawValue == frameworkFolder.lastPathComponent }) else {
                continue
            }

            // Get model folders within this framework folder
            guard let modelFolders = try? fm.contentsOfDirectory(at: frameworkFolder, includingPropertiesForKeys: [.isDirectoryKey]) else {
                continue
            }

            for modelFolder in modelFolders {
                var isModelDir: ObjCBool = false
                guard fm.fileExists(atPath: modelFolder.path, isDirectory: &isModelDir), isModelDir.boolValue else {
                    continue
                }

                let modelId = modelFolder.lastPathComponent

                // Try to use framework-specific storage strategy first
                if let storageStrategy = ModuleRegistry.shared.storageStrategy(for: framework) {
                    if let (format, size) = storageStrategy.detectModel(in: modelFolder) {
                        // Use the folder path as the model path for directory-based models
                        let modelPath = storageStrategy.findModelPath(modelId: modelId, in: modelFolder) ?? modelFolder

                        let category = ModelCategory.from(format: format, frameworks: [framework])
                        let modelInfo = ModelInfo(
                            id: modelId,
                            name: generateModelName(from: modelFolder),
                            category: category,
                            format: format,
                            localPath: modelPath,
                            downloadSize: size,
                            memoryRequired: estimateMemoryUsage(fileSize: size, format: format),
                            compatibleFrameworks: [framework],
                            preferredFramework: framework,
                            contextLength: category == .language ? 2048 : nil,
                            supportsThinking: false,
                            tags: [],
                            description: nil
                        )
                        models.append(modelInfo)
                        logger.info("Discovered \(framework.rawValue) model: \(modelId) using storage strategy")
                        continue
                    }
                }

                // Fallback: Generic detection for single-file models
                if let modelInfo = await detectModelInFolder(modelFolder, framework: framework) {
                    models.append(modelInfo)
                    logger.info("Discovered \(framework.rawValue) model: \(modelId) using generic detection")
                }
            }
        }

        return models
    }

    /// Detect a single-file model in a folder (for non-directory-based models like GGUF)
    private func detectModelInFolder(_ folder: URL, framework: InferenceFramework) async -> ModelInfo? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else {
            return nil
        }

        // Find model files in this folder
        let modelExtensions = ["gguf", "ggml", "onnx", "mlmodel", "mlpackage", "tflite", "safetensors", "pte"]
        for file in files {
            let ext = file.pathExtension.lowercased()
            if modelExtensions.contains(ext), let format = detectFormatFromExtension(ext) {
                let fileSize = FileOperationsUtilities.fileSize(at: file) ?? 0
                let modelId = folder.lastPathComponent
                let category = ModelCategory.from(format: format, frameworks: [framework])

                return ModelInfo(
                    id: modelId,
                    name: generateModelName(from: folder),
                    category: category,
                    format: format,
                    localPath: file,
                    downloadSize: fileSize,
                    memoryRequired: estimateMemoryUsage(fileSize: fileSize, format: format),
                    compatibleFrameworks: [framework],
                    preferredFramework: framework,
                    contextLength: category == .language ? 2048 : nil,
                    supportsThinking: false,
                    tags: [],
                    description: nil
                )
            }
        }

        return nil
    }

    // MARK: - Bundle Models

    private func discoverBundleModels() -> [ModelInfo]? {
        var models: [ModelInfo] = []

        let bundle = Bundle.main
        let modelExtensions = ["mlmodel", "mlmodelc", "mlpackage", "tflite", "onnx", "gguf"]

        for ext in modelExtensions {
            if let urls = bundle.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                for url in urls {
                    guard let format = detectFormatFromExtension(ext) else { continue }

                    let fileSize = FileOperationsUtilities.fileSize(at: url) ?? 0
                    let modelId = url.deletingPathExtension().lastPathComponent
                    let frameworks = detectCompatibleFrameworks(for: format)
                    let category = ModelCategory.from(format: format, frameworks: frameworks)

                    let modelInfo = ModelInfo(
                        id: modelId,
                        name: generateModelName(from: url),
                        category: category,
                        format: format,
                        localPath: url,
                        downloadSize: fileSize,
                        memoryRequired: estimateMemoryUsage(fileSize: fileSize, format: format),
                        compatibleFrameworks: frameworks,
                        preferredFramework: frameworks.first,
                        contextLength: category == .language ? 2048 : nil,
                        supportsThinking: false,
                        tags: ["bundled"],
                        description: nil
                    )
                    models.append(modelInfo)
                }
            }
        }

        return models.isEmpty ? nil : models
    }

    // MARK: - Helper Methods

    private func detectCompatibleFrameworks(for format: ModelFormat) -> [InferenceFramework] {
        switch format {
        case .mlmodel, .mlpackage:
            return [.coreML]
        case .tflite:
            return [.tensorFlowLite]
        case .onnx, .ort:
            return [.onnx]
        case .safetensors:
            return [.mlx]
        case .gguf, .ggml:
            return [.llamaCpp]
        case .pte:
            return [.execuTorch]
        default:
            return []
        }
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
