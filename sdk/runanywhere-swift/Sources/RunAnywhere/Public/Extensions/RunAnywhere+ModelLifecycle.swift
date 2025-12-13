import Combine
import Foundation

// MARK: - Model Lifecycle Tracking

/// Extension for tracking model lifecycle across all modalities (LLM, STT, TTS)
/// Provides observability for model state changes
public extension RunAnywhere {

    // MARK: - Lifecycle Tracker Access

    /// Get the lifecycle tracker for observing model state changes
    @MainActor static var modelLifecycle: ModelLifecycleTracker {
        ModelLifecycleTracker.shared
    }

    /// Subscribe to model lifecycle events
    /// - Returns: A publisher that emits model lifecycle events
    @MainActor static var modelLifecycleEvents: AnyPublisher<ModelLifecycleEvent, Never> {
        ModelLifecycleTracker.shared.lifecycleEvents.eraseToAnyPublisher()
    }

    // MARK: - State Queries

    /// Get currently loaded model for a specific modality
    /// - Parameter modality: The modality to check (llm, stt, tts)
    /// - Returns: The loaded model state, or nil if no model is loaded
    @MainActor
    static func loadedModel(for modality: Modality) -> LoadedModelState? {
        ModelLifecycleTracker.shared.loadedModel(for: modality)
    }

    /// Check if a model is loaded for a specific modality
    /// - Parameter modality: The modality to check
    /// - Returns: True if a model is currently loaded
    @MainActor
    static func isModelLoaded(for modality: Modality) -> Bool {
        ModelLifecycleTracker.shared.isModelLoaded(for: modality)
    }

    /// Get all currently loaded models across all modalities
    /// - Returns: Array of all loaded model states
    @MainActor
    static func allLoadedModels() -> [LoadedModelState] {
        ModelLifecycleTracker.shared.allLoadedModels()
    }

    // MARK: - Lifecycle-Tracked Loading

    /// Load a model with lifecycle tracking
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - modality: The modality for this model (defaults to .llm)
    /// - Throws: SDKError if loading fails
    @MainActor
    static func loadModelWithTracking(_ modelId: String, modality: Modality = .llm) async throws {
        // Get orchestrator and delegate to internal service
        let orchestrator = await serviceContainer.modelLoadingOrchestrator

        do {
            switch modality {
            case .llm:
                let result = try await orchestrator.loadLLMModel(modelId)
                // Set the loaded model in the generation service
                if let loadedModel = result.loadedModel {
                    serviceContainer.generationService.setCurrentModel(loadedModel)
                }
            case .stt:
                _ = try await orchestrator.loadSTTModel(modelId)
            case .tts:
                _ = try await orchestrator.loadTTSModel(modelId)
            default:
                break
            }
        } catch {
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

        switch modality {
        case .llm:
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
