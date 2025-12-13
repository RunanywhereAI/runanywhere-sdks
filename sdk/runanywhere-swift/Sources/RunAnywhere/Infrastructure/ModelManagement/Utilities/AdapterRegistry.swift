//
//  AdapterRegistry.swift
//  RunAnywhere SDK
//
//  Registry for managing framework adapters
//

import Foundation

/// Registry for all framework adapters (text, voice, image, etc.)
/// Manages adapter registration, retrieval, and model-to-adapter matching
public final class AdapterRegistry {
    private let registry = UnifiedServiceRegistry()

    // Legacy storage for backward compatibility
    private var adapters: [LLMFramework: FrameworkAdapter] = [:]
    private let queue = DispatchQueue(label: "com.runanywhere.adapterRegistry", attributes: .concurrent)

    // MARK: - Registration

    /// Register a framework adapter with optional priority
    /// Higher priority adapters are preferred (default: 100)
    /// - Parameters:
    ///   - adapter: The adapter to register
    ///   - priority: Priority level (higher = preferred)
    public func register(_ adapter: FrameworkAdapter, priority: Int = 100) {
        // Register in new unified registry
        Task {
            await registry.register(adapter, priority: priority)
        }

        // Also register in legacy storage for backward compatibility
        queue.async(flags: .barrier) {
            self.adapters[adapter.framework] = adapter
        }

        // Call external services outside of the queue to prevent deadlocks
        Task { @MainActor in
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
    /// - Parameter framework: The framework to look up
    /// - Returns: The adapter if registered
    public func getAdapter(for framework: LLMFramework) -> FrameworkAdapter? {
        queue.sync {
            return adapters[framework]
        }
    }

    /// Find best adapter for a model (uses unified registry)
    /// - Parameters:
    ///   - model: The model to find an adapter for
    ///   - modality: Optional modality filter
    /// - Returns: The best matching adapter
    public func findBestAdapter(for model: ModelInfo, modality: FrameworkModality? = nil) async -> FrameworkAdapter? {
        // Determine modality if not provided
        let targetModality = modality ?? determineModality(for: model)

        // Use unified registry
        return await registry.findBestAdapter(for: model, modality: targetModality)
    }

    /// Find all adapters capable of handling a model
    /// - Parameters:
    ///   - model: The model to find adapters for
    ///   - modality: Optional modality filter
    /// - Returns: Array of capable adapters in priority order
    public func findAllAdapters(for model: ModelInfo, modality: FrameworkModality? = nil) async -> [FrameworkAdapter] {
        // Determine modality if not provided
        let targetModality = modality ?? determineModality(for: model)

        // Use unified registry
        return await registry.findAdapters(for: model, modality: targetModality)
    }

    /// Synchronous version for backward compatibility
    /// - Parameter model: The model to find an adapter for
    /// - Returns: The best matching adapter
    public func findBestAdapterSync(for model: ModelInfo) -> FrameworkAdapter? {
        return queue.sync {
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

    // MARK: - Query Methods

    /// Get all registered adapters
    /// - Returns: Dictionary of frameworks to adapters
    public func getRegisteredAdapters() -> [LLMFramework: FrameworkAdapter] {
        queue.sync {
            return adapters
        }
    }

    /// Get available frameworks
    /// - Returns: Array of registered framework types
    public func getAvailableFrameworks() -> [LLMFramework] {
        queue.sync {
            return Array(adapters.keys)
        }
    }

    /// Get frameworks that support a specific modality
    /// - Parameter modality: The modality to filter by
    /// - Returns: Array of frameworks supporting that modality
    public func getFrameworks(for modality: FrameworkModality) -> [LLMFramework] {
        queue.sync {
            return adapters.compactMap { framework, adapter in
                adapter.supportedModalities.contains(modality) ? framework : nil
            }
        }
    }

    /// Get detailed framework availability information
    /// - Returns: Array of availability info for all frameworks
    public func getFrameworkAvailability() -> [FrameworkAvailability] {
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

    // MARK: - Private Helpers

    /// Determine modality from model info
    private func determineModality(for model: ModelInfo) -> FrameworkModality {
        // Check if it's a speech model
        if model.category == .speechRecognition || model.id.lowercased().contains("whisper") {
            return .voiceToText
        }

        // Default to text-to-text for LLMs
        return .textToText
    }

    private func getRecommendedUseCases(_ framework: LLMFramework, adapter: FrameworkAdapter?) -> [String] {
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
