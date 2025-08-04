import Foundation

/// The main entry point for the RunAnywhere SDK
public class RunAnywhereSDK {
    /// Shared instance of the SDK
    public static let shared: RunAnywhereSDK = RunAnywhereSDK()

    /// Current configuration
    private var configuration: Configuration?

    /// Service container for dependency injection
    private let serviceContainer: ServiceContainer

    /// Currently loaded model
    private var currentModel: ModelInfo?
    private var currentService: LLMService?

    /// Private initializer to enforce singleton pattern
    private init() {
        self.serviceContainer = ServiceContainer()
        setupServices()
    }

    // MARK: - Public API

    /// Initialize the SDK with the provided configuration
    /// - Parameter config: The configuration to use
    public func initialize(configuration: Configuration) async throws {
        self.configuration = configuration

        // Validate configuration
        try await serviceContainer.configurationValidator.validate(configuration)

        // Bootstrap all services with configuration
        try await serviceContainer.bootstrap(with: configuration)

        // Start monitoring services if enabled
        if configuration.enableRealTimeDashboard {
            await serviceContainer.performanceMonitor.startMonitoring()
        }
    }

    /// Load a model by identifier
    /// - Parameter modelIdentifier: The model to load
    /// - Returns: Information about the loaded model
    @discardableResult
    public func loadModel(_ modelIdentifier: String) async throws -> ModelInfo {
        guard configuration != nil else {
            throw SDKError.notInitialized
        }

        // Load model through the loading service
        let loadedModel = try await serviceContainer.modelLoadingService.loadModel(modelIdentifier)

        self.currentModel = loadedModel.model
        self.currentService = loadedModel.service

        // Set the loaded model in the generation service
        serviceContainer.generationService.setCurrentModel(loadedModel)

        // Update last used date in metadata
        let metadataStore = ModelMetadataStore()
        metadataStore.updateLastUsed(for: modelIdentifier)

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

    /// Generate text using the loaded model
    /// - Parameters:
    ///   - prompt: The prompt to generate from
    ///   - options: Generation options
    /// - Returns: The generation result
    public func generate(
        prompt: String,
        options: GenerationOptions? = nil
    ) async throws -> GenerationResult {
        guard configuration != nil else {
            throw SDKError.notInitialized
        }

        guard currentModel != nil else {
            throw SDKError.modelNotFound("No model loaded")
        }

        // Get effective settings from configuration
        let effectiveSettings = await serviceContainer.configurationService.getGenerationSettings()

        // Create options with configuration defaults if not provided
        let effectiveOptions = options ?? GenerationOptions(
            maxTokens: effectiveSettings.maxTokens,
            temperature: effectiveSettings.temperature,
            topP: effectiveSettings.topP
        )

        return try await serviceContainer.generationService.generate(
            prompt: prompt,
            options: effectiveOptions
        )
    }

    /// Generate text as a stream
    /// - Parameters:
    ///   - prompt: The prompt to generate from
    ///   - options: Generation options
    /// - Returns: An async stream of generated text chunks
    public func generateStream(
        prompt: String,
        options: GenerationOptions? = nil
    ) -> AsyncThrowingStream<String, Error> {
        guard configuration != nil else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: SDKError.notInitialized)
            }
        }

        guard currentModel != nil else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: SDKError.modelNotFound("No model loaded"))
            }
        }

        return AsyncThrowingStream { continuation in
            Task {
                // Get effective settings from configuration
                let effectiveSettings = await serviceContainer.configurationService.getGenerationSettings()

                // Create options with configuration defaults if not provided
                let effectiveOptions = options ?? GenerationOptions(
                    maxTokens: effectiveSettings.maxTokens,
                    temperature: effectiveSettings.temperature,
                    topP: effectiveSettings.topP
                )

                // Get the actual stream
                let stream = serviceContainer.streamingService.generateStream(
                    prompt: prompt,
                    options: effectiveOptions
                )

                // Forward all values from the inner stream
                do {
                    for try await chunk in stream {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// List available models
    /// - Returns: Array of available models
    public func listAvailableModels() async throws -> [ModelInfo] {
        guard configuration != nil else {
            throw SDKError.notInitialized
        }

        // Always discover local models to ensure we have the latest
        let discoveredModels = await serviceContainer.modelRegistry.discoverModels()

        // Also check metadata store for any persisted models
        let metadataStore = ModelMetadataStore()
        let storedModels = metadataStore.loadStoredModels()

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
        guard configuration != nil else {
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
        guard configuration != nil else {
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

    /// Register a framework adapter
    /// - Parameter adapter: The framework adapter to register
    public func registerFrameworkAdapter(_ adapter: FrameworkAdapter) {
        serviceContainer.adapterRegistry.register(adapter)
    }

    /// Get the list of registered framework adapters
    /// - Returns: Dictionary of registered adapters by framework
    public func getRegisteredAdapters() -> [LLMFramework: FrameworkAdapter] {
        return serviceContainer.adapterRegistry.getRegisteredAdapters()
    }

    /// Get available frameworks on this device (based on registered adapters)
    /// - Returns: Array of frameworks that have registered adapters
    public func getAvailableFrameworks() -> [LLMFramework] {
        return serviceContainer.adapterRegistry.getAvailableFrameworks()
    }

    /// Get detailed framework availability information
    /// - Returns: Array of framework availability details
    public func getFrameworkAvailability() -> [FrameworkAvailability] {
        return serviceContainer.adapterRegistry.getFrameworkAvailability()
    }

    /// Get models for a specific framework
    /// - Parameter framework: The framework to filter models for
    /// - Returns: Array of models compatible with the framework
    public func getModelsForFramework(_ framework: LLMFramework) -> [ModelInfo] {
        let criteria = ModelCriteria(framework: framework)
        return serviceContainer.modelRegistry.filterModels(by: criteria)
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

    // MARK: - Configuration Management

    /// Set the temperature for text generation (0.0 - 2.0)
    public func setTemperature(_ value: Float) async {
        await serviceContainer.configurationService.setTemperature(value)
    }

    /// Set the maximum tokens for text generation
    public func setMaxTokens(_ value: Int) async {
        await serviceContainer.configurationService.setMaxTokens(value)
    }

    /// Set the top-p sampling parameter (0.0 - 1.0)
    public func setTopP(_ value: Float) async {
        await serviceContainer.configurationService.setTopP(value)
    }

    /// Set the top-k sampling parameter
    public func setTopK(_ value: Int) async {
        await serviceContainer.configurationService.setTopK(value)
    }

    /// Get current generation settings
    public func getGenerationSettings() async -> DefaultGenerationSettings {
        return await serviceContainer.configurationService.getGenerationSettings()
    }

    /// Reset all user overrides to SDK defaults
    public func resetGenerationSettings() async {
        await serviceContainer.configurationService.clearUserOverrides()
    }

    /// Update generation settings from remote configuration
    /// This would typically be called when receiving configuration from your server
    public func updateRemoteConfiguration(_ config: [String: Any]) async {
        await serviceContainer.configurationService.updateRemoteSettings(config)
    }

    /// Sync user preferences to remote server
    /// This sends the current user settings to your backend
    public func syncUserPreferences() async throws {
        try await serviceContainer.configurationService.syncUserPreferences()
    }

    /// Register a callback for when settings change
    public func onGenerationSettingsChanged(_ callback: @escaping (DefaultGenerationSettings) -> Void) async {
        await serviceContainer.configurationService.onSettingsChanged(callback)
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
    ) {
        let metadataStore = ModelMetadataStore()
        metadataStore.updateThinkingSupport(
            for: modelId,
            supportsThinking: supportsThinking,
            thinkingTagPattern: thinkingTagPattern
        )

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


    // MARK: - Private Methods

    private func setupServices() {
        // Services will be registered in the ServiceContainer
    }
}

// MARK: - Internal Service Container Access

extension RunAnywhereSDK {
    /// Access to performance monitoring
    public var performanceMonitor: PerformanceMonitor {
        serviceContainer.performanceMonitor
    }

    /// Access to benchmarking
    public var benchmarkSuite: BenchmarkRunner {
        serviceContainer.benchmarkRunner
    }

    /// Access to file manager for storage operations
    public var fileManager: SimplifiedFileManager {
        serviceContainer.fileManager
    }

    /// Access to A/B testing
    public var abTesting: ABTestRunner {
        serviceContainer.abTestRunner
    }
}
