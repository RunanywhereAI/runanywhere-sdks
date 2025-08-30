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
    public func initialize(with configuration: Configuration) async {
        logger.info("Initializing registry with configuration")

        // Load pre-configured models
        await loadPreconfiguredModels()

        // Discover local models that are already downloaded
        logger.debug("Discovering local models")
        let localModels = await modelDiscovery.discoverLocalModels()
        logger.info("Found \(localModels.count) local models")
        for model in localModels {
            registerModel(model)
        }

        // Discover models from providers
        for provider in configuration.modelProviders where provider.enabled {
            logger.debug("Discovering models from provider")
            await discoverModelsFromProvider(provider)
        }

        logger.info("Registry initialization complete")
    }

    public func discoverModels() async -> [ModelInfo] {
        // Discover local models from disk and register them
        let localModels = await modelDiscovery.discoverLocalModels()
        for model in localModels {
            registerModel(model)
        }

        // Return all registered models (both pre-configured and discovered)
        return accessQueue.sync {
            Array(models.values)
        }
    }

    public func registerModel(_ model: ModelInfo) {
        // Validate model before registering
        guard !model.id.isEmpty else {
            logger.error("Attempted to register model with empty ID")
            return
        }

        logger.debug("Registering model: \(model.id) - \(model.name)")
        accessQueue.async(flags: .barrier) {
            self.models[model.id] = model
            self.logger.info("Successfully registered model: \(model.id)")
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

            // Context length filters
            if let minContext = criteria.minContextLength,
               model.contextLength < minContext {
                return false
            }

            if let maxContext = criteria.maxContextLength,
               model.contextLength > maxContext {
                return false
            }

            // Hardware requirements
            if let requiresNeuralEngine = criteria.requiresNeuralEngine,
               requiresNeuralEngine {
                let hasRequirement = model.hardwareRequirements.contains { req in
                    if case .requiresNeuralEngine = req {
                        return true
                    }
                    return false
                }
                if !hasRequirement {
                    return false
                }
            }

            if let requiresGPU = criteria.requiresGPU,
               requiresGPU {
                let hasRequirement = model.hardwareRequirements.contains { req in
                    if case .requiresGPU = req {
                        return true
                    }
                    return false
                }
                if !hasRequirement {
                    return false
                }
            }

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
        supportsThinking: Bool = false,
        thinkingTagPattern: ThinkingTagPattern? = nil
    ) -> ModelInfo {
        let modelId = generateModelId(from: url)

        // Detect format from URL
        let format = detectFormatFromURL(url)

        let modelInfo = ModelInfo(
            id: modelId,
            name: name,
            format: format,
            downloadURL: url,
            localPath: nil,
            estimatedMemory: estimatedSize ?? estimateMemoryFromURL(url),
            contextLength: 2048, // Default context length
            downloadSize: nil, // Will be determined during download
            checksum: nil,
            compatibleFrameworks: [framework],
            preferredFramework: framework,
            hardwareRequirements: [],
            tokenizerFormat: nil,
            metadata: ModelInfoMetadata(
                tags: ["user-added", framework.rawValue.lowercased()],
                description: "User-added model"
            ),
            alternativeDownloadURLs: [],
            supportsThinking: supportsThinking,
            thinkingTagPattern: thinkingTagPattern
        )

        registerModel(modelInfo)
        return modelInfo
    }

    // MARK: - Private Methods

    private func loadPreconfiguredModels() async {
        logger.debug("Loading pre-configured models")

        // Load models from repository
        // Only load models for frameworks that have registered adapters
        let availableFrameworks = ServiceContainer.shared.adapterRegistry.getAvailableFrameworks()
        logger.debug("Available frameworks: \(availableFrameworks.map { $0.rawValue }.joined(separator: ", "))")

        // Load stored models from service
        let modelMetadataService = await ServiceContainer.shared.modelMetadataService
        do {
            // Load all stored models and filter later
            var storedModels = try await modelMetadataService.loadStoredModels()

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
                registerModel(model)
            }
        } catch {
            logger.error("Failed to load stored models: \(error)")
        }
    }

    private func discoverModelsFromProvider(_ provider: ModelProviderConfig) async {
        // Placeholder for provider-specific discovery
        // Would connect to HuggingFace, Kaggle, etc.
    }

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
