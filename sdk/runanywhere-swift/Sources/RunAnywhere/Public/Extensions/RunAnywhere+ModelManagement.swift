import Foundation

// MARK: - Model Management Extensions (Event-Based)

public extension RunAnywhere {

    /// Load a model by identifier and return model info
    /// - Parameter modelIdentifier: The model to load
    /// - Returns: Information about the loaded model
    @discardableResult
    static func loadModelWithInfo(_ modelIdentifier: String) async throws -> ModelInfo {
        await events.publish(SDKModelEvent.loadStarted(modelId: modelIdentifier))

        do {
            // Use existing service logic directly
            let loadedModel = try await RunAnywhere.serviceContainer.modelLoadingService.loadModel(modelIdentifier)

            // IMPORTANT: Set the loaded model in the generation service
            RunAnywhere.serviceContainer.generationService.setCurrentModel(loadedModel)

            await events.publish(SDKModelEvent.loadCompleted(modelId: modelIdentifier))
            return loadedModel.model
        } catch {
            await events.publish(SDKModelEvent.loadFailed(modelId: modelIdentifier, error: error))
            throw error
        }
    }

    /// Unload the currently loaded model
    static func unloadModel() async throws {
        await events.publish(SDKModelEvent.unloadStarted)

        do {
            // Get the current model ID from generation service
            if let currentModel = RunAnywhere.serviceContainer.generationService.getCurrentModel() {
                let modelId = currentModel.model.id

                // Unload through model loading service
                try await RunAnywhere.serviceContainer.modelLoadingService.unloadModel(modelId)

                // Clear from generation service
                RunAnywhere.serviceContainer.generationService.setCurrentModel(nil)
            }

            await events.publish(SDKModelEvent.unloadCompleted)
        } catch {
            await events.publish(SDKModelEvent.unloadFailed(error))
            throw error
        }
    }

    /// List all available models
    /// - Returns: Array of available models
    static func listAvailableModels() async throws -> [ModelInfo] {
        await events.publish(SDKModelEvent.listRequested)

        do {
            // Use model registry to discover models
            let models = await RunAnywhere.serviceContainer.modelRegistry.discoverModels()
            await events.publish(SDKModelEvent.listCompleted(models: models))
            return models
        } catch {
            await events.publish(SDKModelEvent.listFailed(error))
            throw error
        }
    }

    /// Download a model
    /// - Parameter modelIdentifier: The model to download
    static func downloadModel(_ modelIdentifier: String) async throws {
        await events.publish(SDKModelEvent.downloadStarted(modelId: modelIdentifier))

        do {
            // Get the model info first
            let modelService = await serviceContainer.modelInfoService
            guard let modelInfo = try await modelService.getModel(by: modelIdentifier) else {
                throw SDKError.modelNotFound(modelIdentifier)
            }

            // Use the download service to download the model
            let downloadService = serviceContainer.downloadService
            let downloadTask = try await downloadService.downloadModel(modelInfo)

            // Wait for download completion
            _ = try await downloadTask.result.value

            // Update model info with local path after successful download
            try await modelService.updateDownloadStatus(modelIdentifier, isDownloaded: true)

            await events.publish(SDKModelEvent.downloadCompleted(modelId: modelIdentifier))
        } catch {
            await events.publish(SDKModelEvent.downloadFailed(modelId: modelIdentifier, error: error))
            throw error
        }
    }

    /// Delete a model
    /// - Parameter modelIdentifier: The model to delete
    static func deleteModel(_ modelIdentifier: String) async throws {
        await events.publish(SDKModelEvent.deleteStarted(modelId: modelIdentifier))

        do {
            // Use file manager to delete model
            let fileManager = RunAnywhere.serviceContainer.fileManager
            try fileManager.deleteModel(modelId: modelIdentifier)
            await events.publish(SDKModelEvent.deleteCompleted(modelId: modelIdentifier))
        } catch {
            await events.publish(SDKModelEvent.deleteFailed(modelId: modelIdentifier, error: error))
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
        await events.publish(SDKModelEvent.customModelAdded(name: name, url: url.absoluteString))

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

        await events.publish(SDKModelEvent.builtInModelRegistered(modelId: model.id))
    }
}
