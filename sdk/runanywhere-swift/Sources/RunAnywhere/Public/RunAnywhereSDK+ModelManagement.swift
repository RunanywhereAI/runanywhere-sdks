import Foundation

// MARK: - Model Management APIs

extension RunAnywhereSDK {

    /// Load a model by identifier
    /// - Parameter modelIdentifier: The model to load
    /// - Returns: Information about the loaded model
    @discardableResult
    public func loadModel(_ modelIdentifier: String) async throws -> ModelInfo {
        guard _isInitialized else {
            throw SDKError.notInitialized
        }

        // Load model through the loading service
        let loadedModel = try await serviceContainer.modelLoadingService.loadModel(modelIdentifier)

        self.currentModel = loadedModel.model
        self.currentService = loadedModel.service

        // Set the loaded model in the generation service
        serviceContainer.generationService.setCurrentModel(loadedModel)

        // Update last used date in metadata
        if let dataSyncService = await serviceContainer.dataSyncService {
            try? await dataSyncService.updateModelLastUsed(for: modelIdentifier)
        }

        return loadedModel.model
    }

    /// Unload the currently loaded model
    public func unloadModel() async throws {
        guard let model = currentModel else {
            return
        }

        try await serviceContainer.modelLoadingService.unloadModel(model.id)

        self.currentModel = nil
        self.currentService = nil

        // Clear the model from generation service
        serviceContainer.generationService.setCurrentModel(nil)
    }

    /// List available models
    /// - Returns: Array of available models
    public func listAvailableModels() async throws -> [ModelInfo] {
        guard _isInitialized else {
            throw SDKError.notInitialized
        }

        // Always discover local models to ensure we have the latest
        let discoveredModels = await serviceContainer.modelRegistry.discoverModels()

        // Also check repository for any persisted models
        let storedModels: [ModelInfo]
        if let dataSyncService = await serviceContainer.dataSyncService {
            storedModels = (try? await dataSyncService.loadStoredModels()) ?? []
        } else {
            storedModels = []
        }

        // Merge and deduplicate
        var allModels = discoveredModels
        for storedModel in storedModels {
            if !allModels.contains(where: { $0.id == storedModel.id }) {
                allModels.append(storedModel)
            }
        }

        return allModels
    }

    /// Download a model
    /// - Parameter modelIdentifier: The model to download
    public func downloadModel(_ modelIdentifier: String) async throws -> DownloadTask {
        guard _isInitialized else {
            throw SDKError.notInitialized
        }

        guard let model = serviceContainer.modelRegistry.getModel(by: modelIdentifier) else {
            throw SDKError.modelNotFound(modelIdentifier)
        }

        return try await serviceContainer.downloadService.downloadModel(model)
    }

    /// Delete a downloaded model
    /// - Parameter modelIdentifier: The model to delete
    public func deleteModel(_ modelIdentifier: String) async throws {
        guard _isInitialized else {
            throw SDKError.notInitialized
        }

        // Get model info to find the local path
        guard let modelInfo = serviceContainer.modelRegistry.getModel(by: modelIdentifier) else {
            throw SDKError.modelNotFound(modelIdentifier)
        }

        guard let localPath = modelInfo.localPath else {
            throw SDKError.modelNotFound("Model '\(modelIdentifier)' not downloaded")
        }

        // Extract model ID from the path
        let modelId = localPath.deletingLastPathComponent().lastPathComponent
        try serviceContainer.fileManager.deleteModel(modelId: modelId)
    }

    /// Add a model from URL for download
    /// - Parameters:
    ///   - name: Display name for the model
    ///   - url: Download URL for the model
    ///   - framework: Target framework for the model
    ///   - estimatedSize: Estimated memory usage (optional)
    /// - Returns: The created model info
    public func addModelFromURL(
        name: String,
        url: URL,
        framework: LLMFramework,
        estimatedSize: Int64? = nil,
        supportsThinking: Bool = false,
        thinkingTagPattern: ThinkingTagPattern? = nil
    ) -> ModelInfo {
        return (serviceContainer.modelRegistry as! RegistryService).addModelFromURL(
            name: name,
            url: url,
            framework: framework,
            estimatedSize: estimatedSize,
            supportsThinking: supportsThinking,
            thinkingTagPattern: thinkingTagPattern
        )
    }
    
    /// Register a built-in model (no download required)
    /// - Parameter model: The model info to register
    public func registerBuiltInModel(_ model: ModelInfo) {
        (serviceContainer.modelRegistry as! RegistryService).registerModel(model)
    }

    /// Update thinking support for an existing model
    /// - Parameters:
    ///   - modelId: The model to update
    ///   - supportsThinking: Whether the model supports thinking
    ///   - thinkingTagPattern: The thinking tag pattern to use
    public func updateModelThinkingSupport(
        modelId: String,
        supportsThinking: Bool,
        thinkingTagPattern: ThinkingTagPattern? = nil
    ) async {
        // Update in repository
        if let dataSyncService = await serviceContainer.dataSyncService {
            try? await dataSyncService.updateThinkingSupport(
                for: modelId,
                supportsThinking: supportsThinking,
                thinkingTagPattern: thinkingTagPattern
            )
        }

        // Also update the model in the registry if it exists
        if let existingModel = serviceContainer.modelRegistry.getModel(by: modelId) {
            let updatedModel = ModelInfo(
                id: existingModel.id,
                name: existingModel.name,
                format: existingModel.format,
                downloadURL: existingModel.downloadURL,
                localPath: existingModel.localPath,
                estimatedMemory: existingModel.estimatedMemory,
                contextLength: existingModel.contextLength,
                downloadSize: existingModel.downloadSize,
                checksum: existingModel.checksum,
                compatibleFrameworks: existingModel.compatibleFrameworks,
                preferredFramework: existingModel.preferredFramework,
                hardwareRequirements: existingModel.hardwareRequirements,
                tokenizerFormat: existingModel.tokenizerFormat,
                metadata: existingModel.metadata,
                alternativeDownloadURLs: existingModel.alternativeDownloadURLs,
                supportsThinking: supportsThinking,
                thinkingTagPattern: thinkingTagPattern
            )
            serviceContainer.modelRegistry.updateModel(updatedModel)
        }
    }
}
