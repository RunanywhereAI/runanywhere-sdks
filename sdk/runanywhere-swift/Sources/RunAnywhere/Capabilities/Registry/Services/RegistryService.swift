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

        // Cache models for synchronous lookup by providers
        // This allows providers to check framework compatibility without async calls
        ModelInfoCache.shared.cacheModels(allModels)

        return allModels
    }

    public func registerModel(_ model: ModelInfo) {
        // Validate model before registering
        guard !model.id.isEmpty else {
            logger.error("Attempted to register model with empty ID")
            return
        }

        // Check if model file exists locally and update localPath
        var updatedModel = model
        let fileManager = ServiceContainer.shared.fileManager
        // Try to find the model file if localPath is not already set
        if updatedModel.localPath == nil {
            if let modelFile = fileManager.findModelFile(modelId: model.id) {
                updatedModel.localPath = modelFile
                logger.info("Found local file for model \(model.id): \(modelFile.path)")
            }
        }

        logger.debug("Registering model: \(updatedModel.id) - \(updatedModel.name)")
        accessQueue.async(flags: .barrier) {
            self.models[updatedModel.id] = updatedModel
            self.logger.info("Successfully registered model: \(updatedModel.id)")
        }

        // Also cache for synchronous lookup by providers
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

        // Check if model file exists locally and update localPath
        var updatedModel = model
        let fileManager = ServiceContainer.shared.fileManager
        // Try to find the model file
        if let modelFile = fileManager.findModelFile(modelId: model.id) {
            updatedModel.localPath = modelFile
            logger.info("Found local file for model \(model.id): \(modelFile.path)")
        } else {
            // Clear localPath if file doesn't exist
            updatedModel.localPath = nil
            logger.debug("No local file found for model \(model.id)")
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

            // Context length filters (only for models that have context length)
            if let minContext = criteria.minContextLength,
               let modelContext = model.contextLength,
               modelContext < minContext {
                return false
            }

            if let maxContext = criteria.maxContextLength,
               let modelContext = model.contextLength,
               modelContext > maxContext {
                return false
            }

            // Hardware requirements removed for simplicity

            // Tag filter
            if !criteria.tags.isEmpty {
                let modelTags = model.metadata?.tags ?? []
                let hasAllTags = criteria.tags.allSatisfy { tag in
                    modelTags.contains(tag)
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
                let descMatch = model.metadata?.description?.lowercased()
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
    ///   - name: Display name for the model
    ///   - url: Download URL for the model
    ///   - framework: Target framework for the model
    ///   - estimatedSize: Estimated memory usage (optional)
    /// - Returns: The created model info
    public func addModelFromURL(
        name: String,
        url: URL,
        framework: LLMFramework,
        estimatedSize: Int64? = nil,
        supportsThinking: Bool = false
    ) -> ModelInfo {
        let modelId = generateModelId(from: url)

        // Detect format from URL
        let format = detectFormatFromURL(url)

        // Determine category based on framework
        let category = ModelCategory.from(framework: framework)

        let modelInfo = ModelInfo(
            id: modelId,
            name: name,
            category: category,
            format: format,
            downloadURL: url,
            localPath: nil,
            downloadSize: nil, // Will be determined during download
            memoryRequired: estimatedSize ?? estimateMemoryFromURL(url),
            compatibleFrameworks: [framework],
            preferredFramework: framework,
            contextLength: category == .language ? 2048 : nil, // Only for language models
            supportsThinking: supportsThinking,
            metadata: ModelInfoMetadata(
                tags: ["user-added", framework.rawValue.lowercased()],
                description: "User-added model"
            )
        )

        registerModel(modelInfo)
        return modelInfo
    }

    // MARK: - Private Methods

    private func loadPreconfiguredModels() async {
        logger.debug("Loading pre-configured models")

        // First, try to load models from configuration (remote or cached)
        _ = await ServiceContainer.shared.configurationService.getConfiguration()

        // Model catalog removed from configuration for simplicity
        do {
            logger.debug("No models in configuration, falling back to stored models")

            // Fallback: Load models from repository
            // Only load models for frameworks that have registered adapters
            let availableFrameworks = ServiceContainer.shared.adapterRegistry.getAvailableFrameworks()
            logger.debug("Available frameworks: \(availableFrameworks.map { $0.rawValue }.joined(separator: ", "))")

            // Load stored models from service
            let modelInfoService = await ServiceContainer.shared.modelInfoService
            do {
                // Load all stored models and filter later
                var storedModels = try await modelInfoService.loadStoredModels()

                if !availableFrameworks.isEmpty {
                    // Filter for available frameworks
                    storedModels = storedModels.filter { model in
                        model.compatibleFrameworks.contains { availableFrameworks.contains($0) }
                    }
                    logger.info("Loading \(storedModels.count) models for available frameworks")
                } else {
                    logger.info("No framework adapters registered, loading all \(storedModels.count) stored models")
                }

                for model in storedModels {
                    logger.debug("Registering stored model: \(model.id) with localPath: \(model.localPath?.path ?? "nil")")
                    registerModel(model)
                }
            } catch {
                logger.error("Failed to load stored models: \(error)")
            }
        }
    }

    // Provider discovery removed - no longer needed

    // MARK: - URL Helper Methods

    private func generateModelId(from url: URL) -> String {
        let nameWithoutExtension = url.deletingPathExtension().lastPathComponent
        return "user-\(nameWithoutExtension)-\(abs(url.absoluteString.hashValue))"
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
