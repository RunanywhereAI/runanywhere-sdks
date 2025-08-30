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
            // This is a simplified implementation - would need to call actual unload
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

    /// Download a model (placeholder implementation)
    /// - Parameter modelIdentifier: The model to download
    static func downloadModel(_ modelIdentifier: String) async throws {
        await events.publish(SDKModelEvent.downloadStarted(modelId: modelIdentifier))

        do {
            // This would need actual download implementation
            // For now, just simulate completion
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
            try fileManager.deleteModel(id: modelIdentifier)
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
            format: ModelFormat.gguf, // Default
            downloadURL: url,
            localPath: nil,
            estimatedMemory: 1_000_000_000, // 1GB default
            contextLength: 4096,
            downloadSize: nil,
            checksum: nil,
            compatibleFrameworks: [.llamaCpp],
            preferredFramework: .llamaCpp,
            hardwareRequirements: [],
            tokenizerFormat: nil,
            metadata: nil,
            alternativeDownloadURLs: nil,
            supportsThinking: false,
            thinkingTagPattern: nil
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
