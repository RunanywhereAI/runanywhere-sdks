//
//  RunAnywhere+ModelLifecycle.swift
//  RunAnywhere
//
//  Public API for model lifecycle management
//

import Foundation
import Combine

public extension RunAnywhere {

    // MARK: - Model Lifecycle State

    /// Get the lifecycle tracker for observing model state changes
    @MainActor
    static var modelLifecycle: ModelLifecycleTracker {
        ModelLifecycleTracker.shared
    }

    /// Get currently loaded model for a specific modality
    /// - Parameter modality: The modality to check (llm, stt, tts, vlm)
    /// - Returns: The loaded model state, or nil if no model is loaded
    @MainActor
    static func loadedModel(for modality: Modality) -> LoadedModelState? {
        return ModelLifecycleTracker.shared.loadedModel(for: modality)
    }

    /// Check if a model is loaded for a specific modality
    /// - Parameter modality: The modality to check
    /// - Returns: True if a model is currently loaded
    @MainActor
    static func isModelLoaded(for modality: Modality) -> Bool {
        return ModelLifecycleTracker.shared.isModelLoaded(for: modality)
    }

    /// Get all currently loaded models across all modalities
    /// - Returns: Array of all loaded model states
    @MainActor
    static func allLoadedModels() -> [LoadedModelState] {
        return ModelLifecycleTracker.shared.allLoadedModels()
    }

    /// Subscribe to model lifecycle events
    /// - Returns: A publisher that emits model lifecycle events
    @MainActor
    static var modelLifecycleEvents: AnyPublisher<ModelLifecycleEvent, Never> {
        return ModelLifecycleTracker.shared.lifecycleEvents.eraseToAnyPublisher()
    }

    // MARK: - Load Model with Lifecycle Tracking

    /// Load a model with lifecycle tracking
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - modality: The modality for this model (defaults to .llm)
    /// - Throws: SDKError if loading fails
    @MainActor
    static func loadModelWithTracking(_ modelId: String, modality: Modality = .llm) async throws {
        // Get model info
        guard let modelInfo = serviceContainer.modelRegistry.getModel(by: modelId) else {
            throw SDKError.modelNotFound(modelId)
        }

        let framework = modelInfo.preferredFramework ?? .llamaCpp

        // Notify will load
        ModelLifecycleTracker.shared.modelWillLoad(
            modelId: modelId,
            modelName: modelInfo.name,
            framework: framework,
            modality: modality
        )

        do {
            // Load based on modality
            switch modality {
            case .llm:
                try await RunAnywhere.loadModel(modelId)
            case .stt:
                // STT models are loaded through components
                // The component will call modelDidLoad when ready
                break
            case .tts:
                // TTS models are loaded through components
                break
            case .vlm:
                // VLM models use the same path as LLM for now
                try await RunAnywhere.loadModel(modelId)
            default:
                break
            }

            // For LLM/VLM, mark as loaded now
            if modality == .llm || modality == .vlm {
                ModelLifecycleTracker.shared.modelDidLoad(
                    modelId: modelId,
                    modelName: modelInfo.name,
                    framework: framework,
                    modality: modality,
                    memoryUsage: modelInfo.memoryRequired
                )
            }

        } catch {
            ModelLifecycleTracker.shared.modelLoadFailed(
                modelId: modelId,
                modality: modality,
                error: error.localizedDescription
            )
            throw error
        }
    }

    /// Unload a model for a specific modality
    /// - Parameter modality: The modality to unload
    @MainActor
    static func unloadModel(for modality: Modality) async {
        guard let state = ModelLifecycleTracker.shared.loadedModel(for: modality) else {
            return
        }

        ModelLifecycleTracker.shared.modelWillUnload(modelId: state.modelId, modality: modality)

        // Perform unload based on modality
        switch modality {
        case .llm, .vlm:
            do {
                try await serviceContainer.modelLoadingService.unloadModel(state.modelId)
            } catch {
                // Log but continue with lifecycle update
            }
        default:
            // Components handle their own cleanup
            break
        }

        ModelLifecycleTracker.shared.modelDidUnload(modelId: state.modelId, modality: modality)
    }
}
