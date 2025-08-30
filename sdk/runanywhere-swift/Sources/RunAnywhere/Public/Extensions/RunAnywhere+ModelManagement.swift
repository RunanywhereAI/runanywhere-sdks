import Foundation

// MARK: - Model Management Extensions (Event-Based)

public extension RunAnywhere {

    /// Load a model by identifier with comprehensive event reporting
    /// - Parameter modelIdentifier: The model to load
    /// - Returns: Information about the loaded model
    @discardableResult
    static func loadModel(_ modelIdentifier: String) async throws -> ModelInfo {
        await events.publish(SDKModelEvent.loadStarted(modelId: modelIdentifier))

        do {
            // Use existing service logic directly
            let loadedModel = try await RunAnywhere.serviceContainer.modelLoadingService.loadModel(modelIdentifier)

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
            // For now, we'll need to track which model is currently active
            // This is a simplified implementation
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
            let models: [ModelInfo] = [] // Simplified for now
            await events.publish(SDKModelEvent.listCompleted(models: models))
            return models
        } catch {
            await events.publish(SDKModelEvent.listFailed(error))
            throw error
        }
    }


    /// Download a model
    /// - Parameter modelIdentifier: The model to download
    /// - Returns: Download task for monitoring progress
    static func downloadModel(_ modelIdentifier: String) async throws -> DownloadTask {
        await events.publish(SDKModelEvent.downloadStarted(modelId: modelIdentifier))

        do {
            let downloadTask = try await RunAnywhereSDK.shared.downloadModel(modelIdentifier)

            // Monitor download progress
            Task {
                for try await progress in downloadTask.progressStream {
                    await events.publish(SDKModelEvent.downloadProgress(
                        modelId: modelIdentifier,
                        progress: progress.fractionCompleted
                    ))
                }
                await events.publish(SDKModelEvent.downloadCompleted(modelId: modelIdentifier))
            }

            return downloadTask
        } catch {
            await events.publish(SDKModelEvent.downloadFailed(modelId: modelIdentifier, error: error))
            throw error
        }
    }

    /// Delete a downloaded model
    /// - Parameter modelIdentifier: The model to delete
    static func deleteModel(_ modelIdentifier: String) async throws {
        await events.publish(SDKModelEvent.deleteStarted(modelId: modelIdentifier))

        do {
            try await RunAnywhereSDK.shared.deleteModel(modelIdentifier)
            await events.publish(SDKModelEvent.deleteCompleted(modelId: modelIdentifier))
        } catch {
            await events.publish(SDKModelEvent.deleteFailed(modelId: modelIdentifier, error: error))
            throw error
        }
    }

    /// Add a custom model from URL
    /// - Parameters:
    ///   - url: URL to the model file
    ///   - name: Custom name for the model
    ///   - type: Model type
    /// - Returns: Model information
    static func addModelFromURL(
        _ url: URL,
        name: String,
        type: ModelType
    ) -> ModelInfo {
        await events.publish(SDKModelEvent.customModelAdded(name: name, url: url.absoluteString))

        let modelInfo = RunAnywhereSDK.shared.addModelFromURL(
            url,
            name: name,
            type: type,
            subType: nil,
            frameworkHint: nil
        )

        return modelInfo
    }

    /// Register a built-in model
    /// - Parameter model: The model to register
    static func registerBuiltInModel(_ model: ModelInfo) {
        RunAnywhereSDK.shared.registerBuiltInModel(model)

        Task {
            await events.publish(SDKModelEvent.builtInModelRegistered(modelId: model.id))
        }
    }
}
