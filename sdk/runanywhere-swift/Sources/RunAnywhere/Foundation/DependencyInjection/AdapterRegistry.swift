import Foundation

/// Single registry for all framework adapters (text and voice)
public final class AdapterRegistry {
    private var adapters: [LLMFramework: UnifiedFrameworkAdapter] = [:]
    private let queue = DispatchQueue(label: "com.runanywhere.adapterRegistry", attributes: .concurrent)

    // MARK: - Registration

    /// Register a unified framework adapter
    func register(_ adapter: UnifiedFrameworkAdapter) {
        queue.async(flags: .barrier) {
            self.adapters[adapter.framework] = adapter

            // Call the adapter's onRegistration method
            adapter.onRegistration()

            // Register models provided by the adapter
            let models = adapter.getProvidedModels()
            for model in models {
                ServiceContainer.shared.modelRegistry.registerModel(model)
            }

            // Register download strategy if provided
            if let downloadStrategy = adapter.getDownloadStrategy() {
                ServiceContainer.shared.downloadService.registerStrategy(downloadStrategy)
            }
        }
    }

    // MARK: - Retrieval

    /// Get adapter for a specific framework
    func getAdapter(for framework: LLMFramework) -> UnifiedFrameworkAdapter? {
        queue.sync {
            return adapters[framework]
        }
    }

    /// Find best adapter for a model
    func findBestAdapter(for model: ModelInfo) -> UnifiedFrameworkAdapter? {
        queue.sync {
            // First try preferred framework
            if let preferred = model.preferredFramework,
               let adapter = adapters[preferred],
               adapter.canHandle(model: model) {
                return adapter
            }

            // Then try compatible frameworks
            for framework in model.compatibleFrameworks {
                if let adapter = adapters[framework],
                   adapter.canHandle(model: model) {
                    return adapter
                }
            }

            return nil
        }
    }

    /// Get all registered adapters
    func getRegisteredAdapters() -> [LLMFramework: UnifiedFrameworkAdapter] {
        queue.sync {
            return adapters
        }
    }

    /// Get available frameworks
    func getAvailableFrameworks() -> [LLMFramework] {
        queue.sync {
            return Array(adapters.keys)
        }
    }

    /// Get frameworks that support a specific modality
    func getFrameworks(for modality: FrameworkModality) -> [LLMFramework] {
        queue.sync {
            return adapters.compactMap { framework, adapter in
                adapter.supportedModalities.contains(modality) ? framework : nil
            }
        }
    }

    /// Get detailed framework availability
    func getFrameworkAvailability() -> [FrameworkAvailability] {
        queue.sync {
            let registeredFrameworks = Set(adapters.keys)

            return LLMFramework.allCases.map { framework in
                let isAvailable = registeredFrameworks.contains(framework)
                let adapter = adapters[framework]
                return FrameworkAvailability(
                    framework: framework,
                    isAvailable: isAvailable,
                    unavailabilityReason: isAvailable ? nil : "Framework adapter not registered",
                    recommendedFor: getRecommendedUseCases(framework, adapter: adapter),
                    supportedFormats: adapter?.supportedFormats ?? []
                )
            }
        }
    }

    // MARK: - Private Helper Methods


    private func getRecommendedUseCases(_ framework: LLMFramework, adapter: UnifiedFrameworkAdapter?) -> [String] {
        var useCases: [String] = []

        // Add modality-based use cases
        if let adapter = adapter {
            for modality in adapter.supportedModalities {
                switch modality {
                case .textToText:
                    useCases.append("Text generation")
                    useCases.append("Chat & conversations")
                case .voiceToText:
                    useCases.append("Speech recognition")
                    useCases.append("Voice transcription")
                case .textToVoice:
                    useCases.append("Text-to-speech")
                    useCases.append("Voice synthesis")
                case .imageToText:
                    useCases.append("Image captioning")
                    useCases.append("OCR")
                case .textToImage:
                    useCases.append("Image generation")
                case .multimodal:
                    useCases.append("Multimodal AI")
                }
            }
        }

        // Add framework-specific use cases
        switch framework {
        case .llamaCpp:
            useCases.append("Large language models")
            useCases.append("Efficient quantization")
        case .coreML:
            useCases.append("Apple-optimized models")
        case .whisperKit:
            useCases.append("Whisper models")
            useCases.append("Real-time transcription")
        default:
            break
        }

        return Array(Set(useCases)) // Remove duplicates
    }
}
