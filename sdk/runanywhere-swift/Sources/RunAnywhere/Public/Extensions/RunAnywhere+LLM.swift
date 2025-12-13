import Foundation

// MARK: - LLM Model Operations

/// Extension for LLM (Large Language Model) specific operations
/// Model management, downloading, registration for text generation
public extension RunAnywhere {

    // MARK: - Model Loading

    /// Load an LLM model by identifier and return model info
    /// - Parameter modelIdentifier: The model to load
    /// - Returns: Information about the loaded model
    @discardableResult
    static func loadModelWithInfo(_ modelIdentifier: String) async throws -> ModelInfo {
        events.publish(SDKModelEvent.loadStarted(modelId: modelIdentifier))

        do {
            let loadedModel = try await serviceContainer.modelLoadingService.loadModel(modelIdentifier)
            serviceContainer.generationService.setCurrentModel(loadedModel)
            events.publish(SDKModelEvent.loadCompleted(modelId: modelIdentifier))
            return loadedModel.model
        } catch {
            events.publish(SDKModelEvent.loadFailed(modelId: modelIdentifier, error: error))
            throw error
        }
    }

    /// Unload the currently loaded LLM model
    static func unloadLLMModel() async throws {
        events.publish(SDKModelEvent.unloadStarted)

        do {
            if let currentModel = serviceContainer.generationService.getCurrentModel() {
                try await serviceContainer.modelLoadingService.unloadModel(currentModel.model.id)
                serviceContainer.generationService.setCurrentModel(nil)
            }
            events.publish(SDKModelEvent.unloadCompleted)
        } catch {
            events.publish(SDKModelEvent.unloadFailed(error))
            throw error
        }
    }

    // MARK: - Model Discovery

    /// List all available LLM models
    /// - Returns: Array of available language models
    static func listAvailableModels() async throws -> [ModelInfo] {
        events.publish(SDKModelEvent.listRequested)
        let models = await serviceContainer.modelRegistry.discoverModels()
        events.publish(SDKModelEvent.listCompleted(models: models))
        return models
    }

    // MARK: - Model Download

    /// Download an LLM model
    /// - Parameter modelIdentifier: The model to download
    static func downloadModel(_ modelIdentifier: String) async throws {
        events.publish(SDKModelEvent.downloadStarted(modelId: modelIdentifier))

        do {
            let modelService = await serviceContainer.modelInfoService

            // Try to get model from database or registry
            var modelInfo = try await modelService.getModel(by: modelIdentifier)

            if modelInfo == nil {
                // Fallback to registry
                if let registryModel = serviceContainer.modelRegistry.getModel(by: modelIdentifier) {
                    try await modelService.saveModel(registryModel)
                    modelInfo = try await modelService.getModel(by: modelIdentifier)
                }
            }

            guard let info = modelInfo else {
                throw RunAnywhereError.modelNotFound(modelIdentifier)
            }

            // Download the model
            let downloadTask = try await serviceContainer.downloadService.downloadModel(info)
            let localPath = try await downloadTask.result.value

            // Update status
            try await modelService.updateDownloadStatus(modelIdentifier, isDownloaded: true, localPath: localPath)

            if let updatedModel = try await modelService.getModel(by: modelIdentifier) {
                serviceContainer.modelRegistry.updateModel(updatedModel)
            }

            events.publish(SDKModelEvent.downloadCompleted(modelId: modelIdentifier))
        } catch {
            events.publish(SDKModelEvent.downloadFailed(modelId: modelIdentifier, error: error))
            throw error
        }
    }

    /// Delete a downloaded model
    /// - Parameter modelIdentifier: The model to delete
    static func deleteModel(_ modelIdentifier: String) async throws {
        events.publish(SDKModelEvent.deleteStarted(modelId: modelIdentifier))

        do {
            try serviceContainer.fileManager.deleteModel(modelId: modelIdentifier)
            events.publish(SDKModelEvent.deleteCompleted(modelId: modelIdentifier))
        } catch {
            events.publish(SDKModelEvent.deleteFailed(modelId: modelIdentifier, error: error))
            throw error
        }
    }

    // MARK: - Model Registration

    /// Add a custom model from URL
    /// - Parameters:
    ///   - url: URL to the model file
    ///   - name: Display name for the model
    ///   - framework: Target framework (defaults to llamaCpp)
    ///   - estimatedSize: Estimated memory usage (optional)
    ///   - supportsThinking: Whether the model supports thinking/reasoning
    /// - Returns: The created model info
    @discardableResult
    static func addModelFromURL(
        _ url: URL,
        name: String,
        framework: LLMFramework = .llamaCpp,
        estimatedSize: Int64? = nil,
        supportsThinking: Bool = false
    ) -> ModelInfo {
        let modelInfo = serviceContainer.modelRegistry.addModelFromURL(
            name: name,
            url: url,
            framework: framework,
            estimatedSize: estimatedSize,
            supportsThinking: supportsThinking
        )
        events.publish(SDKModelEvent.customModelAdded(name: name, url: url.absoluteString))
        return modelInfo
    }

    /// Register a built-in model
    /// - Parameter model: The model to register
    static func registerBuiltInModel(_ model: ModelInfo) {
        serviceContainer.modelRegistry.registerModel(model)
        events.publish(SDKModelEvent.builtInModelRegistered(modelId: model.id))
    }
}
