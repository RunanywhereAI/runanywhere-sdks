//
//  RunAnywhere+Frameworks.swift
//  RunAnywhere SDK
//
//  Public API for framework discovery and querying.
//

import Foundation

// MARK: - Framework Discovery API

public extension RunAnywhere {

    /// Get all registered frameworks derived from available models
    /// - Returns: Array of available inference frameworks that have models registered
    static func getRegisteredFrameworks() async -> [InferenceFramework] {
        // Derive frameworks from registered models - this is the source of truth
        let allModels = await CppBridge.ModelRegistry.shared.getAll()
        var frameworks: Set<InferenceFramework> = []

        for model in allModels {
            // Add the model's framework (1:1 mapping)
            frameworks.insert(model.framework)
        }

        return Array(frameworks).sorted { $0.displayName < $1.displayName }
    }

    /// Get all registered frameworks for a specific capability
    /// - Parameter capability: The capability/component type to filter by
    /// - Returns: Array of frameworks that provide the specified capability
    static func getFrameworks(for capability: SDKComponent) async -> [InferenceFramework] {
        let allModels = await CppBridge.ModelRegistry.shared.getAll()
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
        case .voice:
            relevantCategories = [.language, .speechRecognition, .speechSynthesis]
        case .embedding:
            // Embedding models could be language or multimodal
            relevantCategories = [.language, .multimodal]
        case .diffusion:
            relevantCategories = [.imageGeneration]
        }

        for model in allModels where relevantCategories.contains(model.category) {
            // Add the model's framework (1:1 mapping)
            frameworks.insert(model.framework)
        }

        return Array(frameworks).sorted { $0.displayName < $1.displayName }
    }
}
