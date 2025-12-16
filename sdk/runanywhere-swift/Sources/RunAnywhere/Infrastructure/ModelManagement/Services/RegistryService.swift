import Foundation

/// Implementation of model registry
public class RegistryService: ModelRegistry {
    private var models: [String: ModelInfo] = [:]
    private var modelsByProvider: [String: [ModelInfo]] = [:]
    private let modelDiscovery: ModelDiscovery
    private let accessQueue = DispatchQueue(label: "com.runanywhere.registry", attributes: .concurrent)
    private let logger = SDKLogger(category: "RegistryService")

    public init() {
        logger.debug("Initializing RegistryService")
        self.modelDiscovery = ModelDiscovery()
    }

    /// Initialize registry with configuration
    public func initialize(with apiKey: String) async {
        logger.info("Initializing registry with configuration")

        // Load pre-configured models
        await loadPreconfiguredModels()

        // Discover local models that are already downloaded
        logger.debug("Discovering local models from cache")
        let localModels = await modelDiscovery.discoverLocalModels()
        logger.info("Found \(localModels.count) cached models on disk")

        // Update existing registered models with discovered local paths
        // This ensures cached downloads are recognized after app restart
        logger.debug("Comparing discovered models with registered models:")
        logger.debug("Registered model IDs: \(Array(models.keys).sorted())")

        for discoveredModel in localModels {
            logger.debug("Processing discovered model: '\(discoveredModel.id)' at \(discoveredModel.localPath?.path ?? "unknown")")

            if let existingModel = getModel(by: discoveredModel.id) {
                // Model already registered - just update its localPath if needed
                if existingModel.localPath == nil && discoveredModel.localPath != nil {
                    var updatedModel = existingModel
                    updatedModel.localPath = discoveredModel.localPath
                    updateModel(updatedModel)
                    logger.info("✅ Updated registered model '\(discoveredModel.id)' with cached localPath: \(discoveredModel.localPath?.lastPathComponent ?? "unknown")")
                } else if existingModel.localPath != nil {
                    logger.debug("Model '\(discoveredModel.id)' already has localPath: \(existingModel.localPath?.lastPathComponent ?? "unknown")")
                }
            } else {
                // New model found on disk - register it
                logger.info("➕ Registering new cached model: \(discoveredModel.id)")
                registerModel(discoveredModel)
            }
        }

        // Model provider discovery will be handled via configuration service
        // once the configuration is loaded from the network
        _ = await ServiceContainer.shared.configurationService.getConfiguration()

        logger.info("Registry initialization complete")
    }

    public func discoverModels() async -> [ModelInfo] {
        // Simply return all registered models
        // Don't auto-discover local models as it causes confusion with download status
        // Models should only be marked as downloaded when explicitly downloaded via the app
        let allModels = accessQueue.sync {
            Array(models.values)
        }

        // Cache models for lookup by providers
        ModelInfoCache.shared.cacheModels(allModels)

        return allModels
    }

    public func registerModel(_ model: ModelInfo) {
        // Validate model before registering
        guard !model.id.isEmpty else {
            logger.error("Attempted to register model with empty ID")
            return
        }

        // Check if model is downloaded and update localPath
        var updatedModel = model
        if updatedModel.localPath == nil, let framework = model.preferredFramework ?? model.compatibleFrameworks.first {
            let fileManager = ServiceContainer.shared.fileManager
            if fileManager.modelFolderExists(modelId: model.id, framework: framework) {
                if let folderURL = try? fileManager.getModelFolderURL(modelId: model.id, framework: framework) {
                    // Resolve actual model path (handles nested folders and single files)
                    updatedModel.localPath = resolveModelPath(in: folderURL)
                    logger.info("Found downloaded model \(model.id) at: \(updatedModel.localPath?.path ?? folderURL.path)")
                }
            }
        }

        logger.debug("Registering model: \(updatedModel.id) - \(updatedModel.name)")
        accessQueue.async(flags: .barrier) {
            self.models[updatedModel.id] = updatedModel
            self.logger.info("Successfully registered model: \(updatedModel.id)")
        }

        // Also cache for lookup by providers
        ModelInfoCache.shared.cacheModels([updatedModel])
    }

    /// Register model and save to database for persistence
    /// - Parameter model: The model to register and persist
    public func registerModelPersistently(_ model: ModelInfo) async {
        // Validate model before registering
        guard !model.id.isEmpty else {
            logger.error("Attempted to register model with empty ID")
            return
        }

        // Check if model is downloaded and update localPath
        var updatedModel = model
        if let framework = model.preferredFramework ?? model.compatibleFrameworks.first {
            let fileManager = ServiceContainer.shared.fileManager
            if fileManager.modelFolderExists(modelId: model.id, framework: framework) {
                if let folderURL = try? fileManager.getModelFolderURL(modelId: model.id, framework: framework) {
                    // Resolve actual model path (handles nested folders and single files)
                    updatedModel.localPath = resolveModelPath(in: folderURL)
                    logger.info("Found downloaded model \(model.id) at: \(updatedModel.localPath?.path ?? folderURL.path)")
                }
            } else {
                updatedModel.localPath = nil
                logger.debug("Model not downloaded: \(model.id)")
            }
        }

        // Register the updated model in memory
        registerModel(updatedModel)

        // Check if model already exists in database to avoid unnecessary saves
        do {
            let modelInfoService = await ServiceContainer.shared.modelInfoService
            let existingModel = try await modelInfoService.getModel(by: updatedModel.id)

            if existingModel == nil {
                // Model doesn't exist in database, save it
                try await modelInfoService.saveModel(updatedModel)
                logger.info("Registered and saved new model persistently: \(updatedModel.id)")
            } else {
                // Model exists, but let's update it with any new information (including localPath)
                try await modelInfoService.saveModel(updatedModel)
                logger.debug("Updated existing model in database: \(updatedModel.id)")
            }
        } catch {
            logger.error("Failed to save model \(updatedModel.id) to database: \(error)")
            // Model is still registered in memory even if database save fails
        }
    }

    public func getModel(by id: String) -> ModelInfo? {
        return accessQueue.sync {
            models[id]
        }
    }

    public func filterModels(by criteria: ModelCriteria) -> [ModelInfo] {
        return accessQueue.sync {
            models.values.filter { model in
            // Framework filter
            if let framework = criteria.framework,
               !model.compatibleFrameworks.contains(framework) {
                return false
            }

            // Format filter
            if let format = criteria.format,
               model.format != format {
                return false
            }

            // Size filter
            if let maxSize = criteria.maxSize,
               let downloadSize = model.downloadSize,
               downloadSize > maxSize {
                return false
            }

            // Tag filter
            if !criteria.tags.isEmpty {
                let hasAllTags = criteria.tags.allSatisfy { tag in
                    model.tags.contains(tag)
                }
                if !hasAllTags {
                    return false
                }
            }

            // Search filter
            if let search = criteria.search, !search.isEmpty {
                let searchLower = search.lowercased()
                let nameMatch = model.name.lowercased().contains(searchLower)
                let idMatch = model.id.lowercased().contains(searchLower)
                let descMatch = model.description?.lowercased()
                    .contains(searchLower) ?? false

                if !nameMatch && !idMatch && !descMatch {
                    return false
                }
            }

            return true
            }
        }
    }

    public func updateModel(_ model: ModelInfo) {
        accessQueue.async(flags: .barrier) {
            self.models[model.id] = model
        }
    }

    public func removeModel(_ id: String) {
        accessQueue.async(flags: .barrier) {
            self.models.removeValue(forKey: id)
        }
    }

    /// Create and register a model from URL
    /// - Parameters:
    ///   - id: Explicit model ID. If nil, a stable ID is generated from the URL filename.
    ///   - name: Display name for the model
    ///   - url: Download URL for the model
    ///   - framework: Target framework for the model
    ///   - category: Model category (e.g., .language, .speechRecognition, .speechSynthesis). If nil, inferred from framework.
    ///   - artifactType: How the model is packaged (archive, single file, etc.). If nil, inferred from URL.
    ///   - estimatedSize: Estimated memory usage (optional)
    /// - Returns: The created model info
    public func addModelFromURL(
        id: String? = nil,
        name: String,
        url: URL,
        framework: InferenceFramework,
        category: ModelCategory? = nil,
        artifactType: ModelArtifactType? = nil,
        estimatedSize: Int64? = nil,
        supportsThinking: Bool = false
    ) -> ModelInfo {
        let modelId = id ?? generateModelId(from: url)

        // Detect format from URL
        let format = detectFormatFromURL(url)

        // Use provided category or infer from framework
        let category = category ?? ModelCategory.from(framework: framework)

        let modelInfo = ModelInfo(
            id: modelId,
            name: name,
            category: category,
            format: format,
            downloadURL: url,
            localPath: nil,
            artifactType: artifactType, // Pass through - ModelInfo will infer if nil
            downloadSize: nil, // Will be determined during download
            memoryRequired: estimatedSize ?? estimateMemoryFromURL(url),
            compatibleFrameworks: [framework],
            preferredFramework: framework,
            contextLength: category == .language ? 2048 : nil, // Only for language models
            supportsThinking: supportsThinking,
            tags: ["user-added", framework.rawValue.lowercased()],
            description: "User-added model"
        )

        registerModel(modelInfo)
        return modelInfo
    }

    // MARK: - Private Methods

    private func loadPreconfiguredModels() async {
        logger.debug("Loading pre-configured models")

        // Load configuration from service
        _ = await ServiceContainer.shared.configurationService.getConfiguration()

        // Load stored models from service
        let modelInfoService = ServiceContainer.shared.modelInfoService
        do {
            let storedModels = try await modelInfoService.loadStoredModels()
            logger.info("Loading \(storedModels.count) stored models")

            for model in storedModels {
                logger.debug("Registering stored model: \(model.id) with localPath: \(model.localPath?.path ?? "nil")")
                registerModel(model)
            }
        } catch {
            logger.error("Failed to load stored models: \(error)")
        }
    }

    // Provider discovery removed - no longer needed

    // MARK: - Path Resolution

    /// Resolve the actual model path from a folder
    /// If the folder contains exactly one item (file or subfolder), use that item
    /// This handles nested directories from archive extraction and single model files
    private func resolveModelPath(in folderURL: URL) -> URL {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ), contents.count == 1, let singleItem = contents.first else {
            return folderURL
        }

        logger.debug("Resolved model path: \(singleItem.lastPathComponent)")
        return singleItem
    }

    // MARK: - URL Helper Methods

    /// Generate a stable model ID from URL
    /// Uses just the filename without extension - simple and predictable
    private func generateModelId(from url: URL) -> String {
        // Remove all extensions (handles .tar.gz, .tar.bz2, etc.)
        var filename = url.lastPathComponent
        let knownExtensions = [
            "gz", "bz2", "tar", "zip", "gguf", "onnx",
            "mlmodel", "mlpackage", "tflite", "safetensors", "pte", "bin"
        ]
        while let ext = filename.split(separator: ".").last,
              knownExtensions.contains(String(ext).lowercased()) {
            filename = String(filename.dropLast(ext.count + 1))
        }
        return filename
    }

    private func detectFormatFromURL(_ url: URL) -> ModelFormat {
        let pathExtension = url.pathExtension.lowercased()

        switch pathExtension {
        case "gguf":
            return .gguf
        case "ggml":
            return .ggml
        case "mlmodel":
            return .mlmodel
        case "mlpackage":
            return .mlpackage
        case "tflite":
            return .tflite
        case "onnx":
            return .onnx
        case "ort":
            return .ort
        case "safetensors":
            return .safetensors
        case "mlx":
            return .mlx
        case "pte":
            return .pte
        case "bin":
            return .bin
        case "weights":
            return .weights
        case "checkpoint":
            return .checkpoint
        default:
            return .unknown
        }
    }

    private func estimateMemoryFromURL(_ url: URL) -> Int64 {
        let filename = url.lastPathComponent.lowercased()

        // Try to extract size from filename patterns
        if filename.contains("7b") {
            return 7_000_000_000
        } else if filename.contains("13b") {
            return 13_000_000_000
        } else if filename.contains("3b") {
            return 3_000_000_000
        } else if filename.contains("1b") {
            return 1_000_000_000
        } else if filename.contains("500m") {
            return 500_000_000
        } else if filename.contains("small") {
            return 500_000_000
        } else if filename.contains("medium") {
            return 2_000_000_000
        } else if filename.contains("large") {
            return 5_000_000_000
        }

        // Default estimate
        return 2_000_000_000
    }
}
