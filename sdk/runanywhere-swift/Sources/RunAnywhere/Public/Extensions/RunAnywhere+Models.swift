import Combine
import Foundation

// MARK: - Model Extensions
// Unified API for model management and lifecycle tracking

public extension RunAnywhere {

    // MARK: - Model Management (CRUD Operations)

    /// Load a model by identifier and return model info
    /// - Parameter modelIdentifier: The model to load
    /// - Returns: Information about the loaded model
    @discardableResult
    static func loadModelWithInfo(_ modelIdentifier: String) async throws -> ModelInfo {
        events.publish(SDKModelEvent.loadStarted(modelId: modelIdentifier))

        do {
            // Use existing service logic directly
            let loadedModel = try await RunAnywhere.serviceContainer.modelLoadingService.loadModel(modelIdentifier)

            // IMPORTANT: Set the loaded model in the generation service
            RunAnywhere.serviceContainer.generationService.setCurrentModel(loadedModel)

            events.publish(SDKModelEvent.loadCompleted(modelId: modelIdentifier))
            return loadedModel.model
        } catch {
            events.publish(SDKModelEvent.loadFailed(modelId: modelIdentifier, error: error))
            throw error
        }
    }

    /// Unload the currently loaded model
    static func unloadModel() async throws {
        events.publish(SDKModelEvent.unloadStarted)

        do {
            // Get the current model ID from generation service
            if let currentModel = RunAnywhere.serviceContainer.generationService.getCurrentModel() {
                let modelId = currentModel.model.id

                // Unload through model loading service
                try await RunAnywhere.serviceContainer.modelLoadingService.unloadModel(modelId)

                // Clear from generation service
                RunAnywhere.serviceContainer.generationService.setCurrentModel(nil)
            }

            events.publish(SDKModelEvent.unloadCompleted)
        } catch {
            events.publish(SDKModelEvent.unloadFailed(error))
            throw error
        }
    }

    /// List all available models
    /// - Returns: Array of available models
    static func listAvailableModels() async throws -> [ModelInfo] {
        events.publish(SDKModelEvent.listRequested)

        // Use model registry to discover models
        let models = await RunAnywhere.serviceContainer.modelRegistry.discoverModels()
        events.publish(SDKModelEvent.listCompleted(models: models))
        return models
    }

    /// Download a model
    /// - Parameter modelIdentifier: The model to download
    static func downloadModel(_ modelIdentifier: String) async throws {
        events.publish(SDKModelEvent.downloadStarted(modelId: modelIdentifier))

        do {
            // Get the model info first
            let modelService = await serviceContainer.modelInfoService

            // Log available models for debugging
            let allModels = try await modelService.loadStoredModels()
            print("[DEBUG] Available models in database: \(allModels.map { $0.id })")
            print("[DEBUG] Looking for model: \(modelIdentifier)")

            guard let modelInfo = try await modelService.getModel(by: modelIdentifier) else {
                print("[ERROR] Model not found in database: \(modelIdentifier)")
                // Try to find in registry as fallback
                if let registryModel = serviceContainer.modelRegistry.getModel(by: modelIdentifier) {
                    print("[DEBUG] Found model in registry, saving to database")
                    try await modelService.saveModel(registryModel)
                    // Now try again
                    guard let savedModel = try await modelService.getModel(by: modelIdentifier) else {
                        throw RunAnywhereError.modelNotFound(modelIdentifier)
                    }
                    // Use the saved model
                    let downloadService = serviceContainer.downloadService
                    let downloadTask = try await downloadService.downloadModel(savedModel)
                    let localPath = try await downloadTask.result.value
                    try await modelService.updateDownloadStatus(modelIdentifier, isDownloaded: true, localPath: localPath)
                    if let updatedModel = try await modelService.getModel(by: modelIdentifier) {
                        serviceContainer.modelRegistry.updateModel(updatedModel)
                    }
                    events.publish(SDKModelEvent.downloadCompleted(modelId: modelIdentifier))
                    return
                }
                throw RunAnywhereError.modelNotFound(modelIdentifier)
            }

            // Use the download service to download the model
            let downloadService = serviceContainer.downloadService
            let downloadTask = try await downloadService.downloadModel(modelInfo)

            // Wait for download completion and get the local path
            let localPath = try await downloadTask.result.value

            // Update model info with local path after successful download
            try await modelService.updateDownloadStatus(modelIdentifier, isDownloaded: true, localPath: localPath)

            // Also update the model in the registry with the new local path
            if let updatedModel = try await modelService.getModel(by: modelIdentifier) {
                serviceContainer.modelRegistry.updateModel(updatedModel)
            }

            events.publish(SDKModelEvent.downloadCompleted(modelId: modelIdentifier))
        } catch {
            events.publish(SDKModelEvent.downloadFailed(modelId: modelIdentifier, error: error))
            throw error
        }
    }

    /// Delete a model
    /// - Parameter modelIdentifier: The model to delete
    static func deleteModel(_ modelIdentifier: String) async throws {
        events.publish(SDKModelEvent.deleteStarted(modelId: modelIdentifier))

        do {
            // Use file manager to delete model
            let fileManager = RunAnywhere.serviceContainer.fileManager
            try fileManager.deleteModel(modelId: modelIdentifier)
            events.publish(SDKModelEvent.deleteCompleted(modelId: modelIdentifier))
        } catch {
            events.publish(SDKModelEvent.deleteFailed(modelId: modelIdentifier, error: error))
            throw error
        }
    }

    /// Add a custom model from URL (simplified implementation)
    /// - Parameters:
    ///   - url: URL to the model
    ///   - name: Display name for the model
    ///   - type: Model type
    /// - Returns: Model information
    static func addModelFromURL(
        _ url: URL,
        name: String,
        type: String
    ) async -> ModelInfo {
        events.publish(SDKModelEvent.customModelAdded(name: name, url: url.absoluteString))

        // Create basic model info (this would need proper implementation)
        let modelInfo = ModelInfo(
            id: UUID().uuidString,
            name: name,
            category: .language, // Default to language model
            format: ModelFormat.gguf, // Default
            downloadURL: url,
            localPath: nil,
            downloadSize: nil,
            memoryRequired: Int64(1024 * 1024 * 1024), // Default 1GB
            compatibleFrameworks: [.llamaCpp],
            preferredFramework: .llamaCpp,
            contextLength: 4096,
            supportsThinking: false,
            metadata: nil
        )

        // Register the model
        RunAnywhere.serviceContainer.modelRegistry.registerModel(modelInfo)

        return modelInfo
    }

    /// Register a built-in model
    /// - Parameter model: The model to register
    static func registerBuiltInModel(_ model: ModelInfo) async {
        // Register the model in the model registry
        RunAnywhere.serviceContainer.modelRegistry.registerModel(model)

        events.publish(SDKModelEvent.builtInModelRegistered(modelId: model.id))
    }

    // MARK: - Model Lifecycle Tracking

    /// Get the lifecycle tracker for observing model state changes
    @MainActor static var modelLifecycle: ModelLifecycleTracker {
        ModelLifecycleTracker.shared
    }

    /// Get currently loaded model for a specific modality
    /// - Parameter modality: The modality to check (llm, stt, tts)
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
    @MainActor static var modelLifecycleEvents: AnyPublisher<ModelLifecycleEvent, Never> {
        return ModelLifecycleTracker.shared.lifecycleEvents.eraseToAnyPublisher()
    }

    /// Load a model with lifecycle tracking
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - modality: The modality for this model (defaults to .llm)
    /// - Throws: SDKError if loading fails
    @MainActor
    static func loadModelWithTracking(_ modelId: String, modality: Modality = .llm) async throws {
        // Get model info
        guard let modelInfo = serviceContainer.modelRegistry.getModel(by: modelId) else {
            throw RunAnywhereError.modelNotFound(modelId)
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
            default:
                break
            }

            // For LLM, mark as loaded now
            if modality == .llm {
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
