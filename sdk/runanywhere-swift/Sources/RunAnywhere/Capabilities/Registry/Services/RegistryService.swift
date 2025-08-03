import Foundation

/// Implementation of model registry
public class RegistryService: ModelRegistry {
    private var models: [String: ModelInfo] = [:]
    private var modelsByProvider: [String: [ModelInfo]] = [:]

    public init() {}

    /// Initialize registry with configuration
    public func initialize(with configuration: Configuration) async {
        // Load pre-configured models
        await loadPreconfiguredModels()

        // Discover models from providers
        for provider in configuration.modelProviders where provider.enabled {
            await discoverModelsFromProvider(provider)
        }
    }

    public func discoverModels() async -> [ModelInfo] {
        // Return all registered models
        return Array(models.values)
    }

    public func registerModel(_ model: ModelInfo) {
        models[model.id] = model
    }

    public func getModel(by id: String) -> ModelInfo? {
        return models[id]
    }

    public func filterModels(by criteria: ModelCriteria) -> [ModelInfo] {
        return models.values.filter { model in
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

    public func updateModel(_ model: ModelInfo) {
        models[model.id] = model
    }

    public func removeModel(_ id: String) {
        models.removeValue(forKey: id)
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
        estimatedSize: Int64? = nil
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
                description: "User-added model from \(url.host ?? "external source")"
            ),
            alternativeDownloadURLs: []
        )

        registerModel(modelInfo)
        return modelInfo
    }

    // MARK: - Private Methods

    private func loadPreconfiguredModels() async {
        // Load some example models
        let exampleModels = [
            ModelInfo(
                id: "llama2-7b-gguf",
                name: "Llama 2 7B GGUF",
                format: .gguf,
                downloadURL: URL(string: "https://example.com/llama2-7b.gguf"),
                estimatedMemory: 7_000_000_000,
                contextLength: 4096,
                downloadSize: 4_000_000_000,
                compatibleFrameworks: [.llamaCpp],
                preferredFramework: .llamaCpp,
                metadata: ModelInfoMetadata(
                    author: "Meta",
                    license: "Llama 2 Community License",
                    tags: ["llm", "7b", "gguf"],
                    description: "Llama 2 7B model in GGUF format"
                )
            ),
            ModelInfo(
                id: "gpt2-coreml",
                name: "GPT-2 CoreML",
                format: .mlpackage,
                downloadURL: URL(string: "https://example.com/gpt2.mlpackage"),
                estimatedMemory: 500_000_000,
                contextLength: 1024,
                downloadSize: 250_000_000,
                compatibleFrameworks: [.coreML],
                preferredFramework: .coreML,
                hardwareRequirements: [.requiresNeuralEngine],
                metadata: ModelInfoMetadata(
                    author: "OpenAI",
                    license: "MIT",
                    tags: ["gpt2", "coreml", "small"],
                    description: "GPT-2 model optimized for CoreML"
                )
            )
        ]

        for model in exampleModels {
            registerModel(model)
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
