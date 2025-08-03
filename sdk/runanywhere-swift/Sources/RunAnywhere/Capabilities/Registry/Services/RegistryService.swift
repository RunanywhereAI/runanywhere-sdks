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
}
