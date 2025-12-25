//
//  RunAnywhere+Frameworks.swift
//  RunAnywhere SDK
//
//  Public API for framework discovery and querying.
//

import Foundation

// MARK: - Framework Discovery API

public extension RunAnywhere {

    /// Get models for a specific framework
    /// - Parameter framework: The framework to query
    /// - Returns: Array of models for the framework
    static func getModelsForFramework(_ framework: InferenceFramework) -> [ModelInfo] {
        EventPublisher.shared.track(FrameworkEvent.modelsRequested(framework: framework.rawValue))

        let models = RunAnywhere.serviceContainer.modelRegistry.filterModels(by: ModelCriteria(framework: framework))

        EventPublisher.shared.track(FrameworkEvent.modelsRetrieved(
            framework: framework.rawValue,
            count: models.count
        ))

        return models
    }

    /// Get all registered frameworks derived from available models
    /// - Returns: Array of available inference frameworks that have models registered
    @MainActor
    static func getRegisteredFrameworks() -> [InferenceFramework] {
        // Derive frameworks from registered models - this is the source of truth
        let allModels = serviceContainer.modelRegistry.filterModels(by: ModelCriteria())
        var frameworks: Set<InferenceFramework> = []

        for model in allModels {
            // Add preferred framework
            if let preferred = model.framework {
                frameworks.insert(preferred)
            }
            // Add all compatible frameworks
            for framework in model.compatibleFrameworks {
                frameworks.insert(framework)
            }
        }

        return Array(frameworks).sorted { $0.displayName < $1.displayName }
    }

    /// Get all registered frameworks for a specific capability
    /// - Parameter capability: The capability type to filter by
    /// - Returns: Array of frameworks that provide the specified capability
    @MainActor
    static func getFrameworks(for capability: CapabilityType) -> [InferenceFramework] {
        let allModels = serviceContainer.modelRegistry.filterModels(by: ModelCriteria())
        var frameworks: Set<InferenceFramework> = []

        // Map capability to model categories
        let relevantCategories: Set<ModelCategory>
        switch capability {
        case .llm:
            relevantCategories = [.language, .multimodal]
        case .stt:
            relevantCategories = [.speechRecognition]
        case .tts:
            relevantCategories = [.speechSynthesis]
        case .vad:
            relevantCategories = [.audio]
        case .speakerDiarization:
            relevantCategories = [.audio]
        }

        for model in allModels where relevantCategories.contains(model.category) {
            if let preferred = model.framework {
                frameworks.insert(preferred)
            }
            for framework in model.compatibleFrameworks {
                frameworks.insert(framework)
            }
        }

        return Array(frameworks).sorted { $0.displayName < $1.displayName }
    }
}
