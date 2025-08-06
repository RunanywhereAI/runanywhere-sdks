import Foundation
import os

/// The main entry point for the RunAnywhere SDK
public class RunAnywhereSDK {
    /// Shared instance of the SDK
    public static let shared: RunAnywhereSDK = RunAnywhereSDK()

    /// Current configuration
    private var configuration: Configuration?
    private var _isInitialized = false

    /// Task that tracks SDK initialization - allows other code to await completion
    private var initializationTask: Task<Void, Error>?

    /// Check if SDK is fully initialized
    public var isInitialized: Bool {
        return _isInitialized
    }

    /// Wait for SDK to be initialized - safe to call from any thread
    public func waitForInitialization() async throws {
        if let initTask = initializationTask {
            try await initTask.value
        } else if !_isInitialized {
            throw SDKError.notInitialized
        }
    }

    /// Private helper to ensure SDK is initialized before proceeding
    private func ensureInitialized() async throws {
        if _isInitialized {
            return // Fast path - already initialized
        }

        if let initTask = initializationTask {
            // Initialization in progress, wait for it
            try await initTask.value
            return
        }

        // Not initialized and no initialization in progress
        throw SDKError.notInitialized
    }

    /// Service container for dependency injection
    private let serviceContainer: ServiceContainer

    /// Currently loaded model
    private var currentModel: ModelInfo?
    private var currentService: LLMService?

    /// Logger for debugging
    private let logger = SDKLogger(category: "RunAnywhereSDK")

    /// Private initializer to enforce singleton pattern
    private init() {
        self.serviceContainer = ServiceContainer.shared  // Use the shared instance!
        setupServices()
        logger.info("🏗️ RunAnywhereSDK singleton created")
    }

    // MARK: - Public API

    /// Initialize the SDK with the provided configuration
    /// - Parameter config: The configuration to use
    public func initialize(configuration: Configuration) async throws {
        // If already initialized or initializing, return/wait
        if _isInitialized {
            logger.info("✅ SDK already initialized")
            return
        }

        if let existingTask = initializationTask {
            logger.info("⏳ SDK initialization in progress, waiting...")
            try await existingTask.value
            return
        }

        logger.info("🚀 Starting SDK initialization with configuration")

        // Create initialization task
        let initTask = Task<Void, Error> { @MainActor in
            do {
                self.configuration = configuration

                // Validate configuration
                try await serviceContainer.configurationValidator.validate(configuration)
                logger.info("✅ Configuration validated")

                // Bootstrap all services with configuration
                try await serviceContainer.bootstrap(with: configuration)
                logger.info("✅ Services bootstrapped")

                // Start monitoring services if enabled
                if configuration.enableRealTimeDashboard {
                    serviceContainer.performanceMonitor.startMonitoring()
                    logger.info("📊 Performance monitoring started")
                }

                // Mark as initialized
                _isInitialized = true

                // Log successful initialization
                logger.info("✅ RunAnywhereSDK initialized successfully - configuration loaded")
            } catch {
                logger.error("❌ SDK initialization failed: \(error)")
                _isInitialized = false
                self.configuration = nil
                self.initializationTask = nil // Clear failed task
                throw error
            }
        }

        self.initializationTask = initTask
        try await initTask.value
    }

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

    /// Generate text using the loaded model
    /// - Parameters:
    ///   - prompt: The prompt to generate from
    ///   - options: Generation options
    /// - Returns: The generation result
    public func generate(
        prompt: String,
        options: GenerationOptions? = nil
    ) async throws -> GenerationResult {
        logger.info("🚀 Starting generation for prompt: \(prompt.prefix(50))...")

        guard _isInitialized else {
            logger.error("❌ SDK not initialized")
            throw SDKError.notInitialized
        }

        logger.debug("✅ SDK is initialized")

        guard let model = currentModel else {
            logger.error("❌ No model loaded")
            throw SDKError.modelNotFound("No model loaded")
        }

        logger.debug("✅ Current model: \(model.name)")

        // Get effective settings from configuration
        logger.debug("🚀 Getting effective settings")
        let effectiveSettings = await getGenerationSettings()

        // Create options with configuration defaults if not provided
        let effectiveOptions = options ?? GenerationOptions(
            maxTokens: effectiveSettings.maxTokens,
            temperature: Float(effectiveSettings.temperature),
            topP: Float(effectiveSettings.topP)
        )

        // Check if analytics is enabled
        let isAnalyticsEnabled = await getAnalyticsEnabled()

        let result: GenerationResult
        if isAnalyticsEnabled {
            result = try await serviceContainer.generationService.generateWithAnalytics(
                prompt: prompt,
                options: effectiveOptions
            )
        } else {
            logger.debug("🚀 Calling GenerationService.generate()")
            result = try await serviceContainer.generationService.generate(
                prompt: prompt,
                options: effectiveOptions
            )
        }

        logger.info("✅ Generation completed successfully")
        return result
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
        guard _isInitialized else {
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
                let effectiveSettings = await getGenerationSettings()

                // Create options with configuration defaults if not provided
                let effectiveOptions = options ?? GenerationOptions(
                    maxTokens: effectiveSettings.maxTokens,
                    temperature: Float(effectiveSettings.temperature),
                    topP: Float(effectiveSettings.topP)
                )

                // Check if analytics is enabled
                let isAnalyticsEnabled = await getAnalyticsEnabled()

                // Get the actual stream
                let stream: AsyncThrowingStream<String, Error>
                if isAnalyticsEnabled {
                    stream = serviceContainer.streamingService.generateStreamWithAnalytics(
                        prompt: prompt,
                        options: effectiveOptions
                    )
                } else {
                    stream = serviceContainer.streamingService.generateStream(
                        prompt: prompt,
                        options: effectiveOptions
                    )
                }

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
        logger.info("🌡️ Setting temperature")
        await serviceContainer.configurationService.updateConfiguration { config in
            var updated = config
            updated.generation.defaults.temperature = Double(value)
            return updated.markUpdated()
        }
        logger.info("✅ Temperature updated")
    }

    /// Set the maximum tokens for text generation
    public func setMaxTokens(_ value: Int) async {
        logger.info("🔢 Setting maxTokens")
        await serviceContainer.configurationService.updateConfiguration { config in
            var updated = config
            updated.generation.defaults.maxTokens = value
            return updated.markUpdated()
        }
        logger.info("✅ MaxTokens updated")
    }

    /// Set the top-p sampling parameter (0.0 - 1.0)
    public func setTopP(_ value: Float) async {
        logger.info("📊 Setting topP")
        await serviceContainer.configurationService.updateConfiguration { config in
            var updated = config
            updated.generation.defaults.topP = Double(value)
            return updated.markUpdated()
        }
        logger.info("✅ TopP updated")
    }

    /// Set the top-k sampling parameter
    public func setTopK(_ value: Int) async {
        logger.info("📊 Setting topK")
        await serviceContainer.configurationService.updateConfiguration { config in
            var updated = config
            updated.generation.defaults.topK = value
            return updated.markUpdated()
        }
        logger.info("✅ TopK updated")
    }

    /// Get current generation settings
    public func getGenerationSettings() async -> DefaultGenerationSettings {
        logger.info("📖 Getting generation settings")

        // Ensure configuration is loaded from database
        await serviceContainer.configurationService.ensureConfigurationLoaded()

        let config = await serviceContainer.configurationService.getConfiguration()

        let defaults = config?.generation.defaults ?? DefaultGenerationSettings()
        let temperature = defaults.temperature
        let maxTokens = defaults.maxTokens
        let topP = defaults.topP
        let topK = defaults.topK ?? SDKConstants.ConfigurationDefaults.topK

        logger.info("📊 Returning generation settings")

        return DefaultGenerationSettings(
            temperature: temperature,
            maxTokens: maxTokens,
            topP: topP,
            topK: topK
        )
    }

    /// Reset all user overrides to SDK defaults
    public func resetGenerationSettings() async {
        logger.info("🔄 Resetting generation settings to defaults")
        await serviceContainer.configurationService.updateConfiguration { _ in
            ConfigurationData() // Returns default configuration
        }
        logger.info("✅ Generation settings reset to defaults")
    }

    /// Sync user preferences to remote server
    public func syncUserPreferences() async {
        do {
            try await serviceContainer.configurationService.syncToCloud()
        } catch {
            // Log error but don't throw to avoid breaking the UI
            logger.error("Failed to sync preferences: \(error)")
        }
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

    // MARK: - SDK Configuration Settings

    /// Set whether cloud routing is enabled
    public func setCloudRoutingEnabled(_ enabled: Bool) async {
        logger.info("☁️ Setting cloud routing enabled")
        await serviceContainer.configurationService.updateConfiguration { config in
            var updated = config
            updated.routing.cloudEnabled = enabled
            return updated.markUpdated()
        }
        logger.info("✅ Cloud routing setting updated")
    }

    /// Get whether cloud routing is enabled
    public func getCloudRoutingEnabled() async -> Bool {
        logger.info("📖 Getting cloud routing enabled setting")
        await serviceContainer.configurationService.ensureConfigurationLoaded()
        let config = await serviceContainer.configurationService.getConfiguration()
        let value = config?.routing.cloudEnabled ?? SDKConstants.ConfigurationDefaults.cloudRoutingEnabled
        logger.info("☁️ Cloud routing enabled retrieved")
        return value
    }

    /// Set privacy mode
    public func setPrivacyMode(_ mode: PrivacyMode) async {
        logger.info("🔒 Setting privacy mode")
        await serviceContainer.configurationService.updateConfiguration { config in
            var updated = config
            updated.routing.privacyMode = mode
            return updated.markUpdated()
        }
        logger.info("✅ Privacy mode setting updated")
    }

    /// Get privacy mode
    public func getPrivacyMode() async -> PrivacyMode {
        logger.info("📖 Getting privacy mode setting")
        await serviceContainer.configurationService.ensureConfigurationLoaded()
        let config = await serviceContainer.configurationService.getConfiguration()
        let value = config?.routing.privacyMode ?? (SDKConstants.ConfigurationDefaults.privacyModeEnabled ? .strict : .standard)
        logger.info("🔒 Privacy mode retrieved")
        return value
    }


    /// Set the routing policy
    public func setRoutingPolicy(_ policy: RoutingPolicy) async {
        logger.info("🛣️ Setting routing policy")
        await serviceContainer.configurationService.updateConfiguration { config in
            var updated = config
            updated.routing.policy = policy
            return updated.markUpdated()
        }
        logger.info("✅ Routing policy updated")
    }

    /// Get the routing policy
    public func getRoutingPolicy() async -> RoutingPolicy {
        logger.info("📖 Getting routing policy")
        await serviceContainer.configurationService.ensureConfigurationLoaded()
        let config = await serviceContainer.configurationService.getConfiguration()
        let value = config?.routing.policy ?? SDKConstants.ConfigurationDefaults.routingPolicy
        logger.info("🛣️ Routing policy retrieved")
        return value
    }


    /// Set the API key
    public func setApiKey(_ apiKey: String?) async {
        logger.info("🔑 Setting API key")
        await serviceContainer.configurationService.updateConfiguration { config in
            var updated = config
            updated.apiKey = apiKey
            return updated.markUpdated()
        }
        logger.info("✅ API key updated")
    }

    /// Get the API key
    public func getApiKey() async -> String? {
        logger.info("📖 Getting API key")
        await serviceContainer.configurationService.ensureConfigurationLoaded()
        let config = await serviceContainer.configurationService.getConfiguration()
        logger.info("🔑 API key retrieved")
        return config?.apiKey
    }

    /// Set whether analytics is enabled
    internal func setAnalyticsEnabled(_ enabled: Bool) async {
        logger.info("📊 Setting analytics enabled")

        do {
            try await ensureInitialized()
        } catch {
            logger.warning("⚠️ SDK not initialized, cannot set analytics setting")
            return
        }

        await serviceContainer.configurationService.updateConfiguration { config in
            var updated = config
            updated.analytics.enabled = enabled
            return updated.markUpdated()
        }
        logger.info("✅ Analytics enabled setting updated")
    }

    /// Get whether analytics is enabled
    internal func getAnalyticsEnabled() async -> Bool {
        logger.info("📖 Getting analytics enabled setting")

        do {
            try await ensureInitialized()
        } catch {
            logger.warning("⚠️ SDK not initialized, returning default analytics setting")
            return SDKConstants.ConfigurationDefaults.analyticsEnabled
        }

        await serviceContainer.configurationService.ensureConfigurationLoaded()
        let config = await serviceContainer.configurationService.getConfiguration()
        let value = config?.analytics.enabled ?? SDKConstants.ConfigurationDefaults.analyticsEnabled
        logger.info("📊 Analytics enabled retrieved: \(value)")
        return value
    }

    /// Set the analytics level
    internal func setAnalyticsLevel(_ level: AnalyticsLevel) async {
        logger.info("📊 Setting analytics level")

        do {
            try await ensureInitialized()
        } catch {
            logger.warning("⚠️ SDK not initialized, cannot set analytics level")
            return
        }

        await serviceContainer.configurationService.updateConfiguration { config in
            var updated = config
            updated.analytics.level = level
            return updated.markUpdated()
        }
        logger.info("✅ Analytics level updated")
    }

    /// Get the analytics level
    internal func getAnalyticsLevel() async -> AnalyticsLevel {
        logger.info("📖 Getting analytics level")

        do {
            try await ensureInitialized()
        } catch {
            logger.warning("⚠️ SDK not initialized, returning default analytics level")
            return SDKConstants.ConfigurationDefaults.analyticsLevel
        }

        await serviceContainer.configurationService.ensureConfigurationLoaded()
        let config = await serviceContainer.configurationService.getConfiguration()
        let value = config?.analytics.level ?? SDKConstants.ConfigurationDefaults.analyticsLevel
        logger.info("📊 Analytics level retrieved: \(value)")
        return value
    }

    /// Set whether live metrics are enabled
    internal func setEnableLiveMetrics(_ enabled: Bool) async {
        logger.info("📊 Setting enable live metrics")

        do {
            try await ensureInitialized()
        } catch {
            logger.warning("⚠️ SDK not initialized, cannot set live metrics")
            return
        }

        await serviceContainer.configurationService.updateConfiguration { config in
            var updated = config
            updated.analytics.liveMetricsEnabled = enabled
            return updated.markUpdated()
        }
        logger.info("✅ Enable live metrics setting updated")
    }

    /// Get whether live metrics are enabled
    internal func getEnableLiveMetrics() async -> Bool {
        logger.info("📖 Getting enable live metrics setting")
        await serviceContainer.configurationService.ensureConfigurationLoaded()
        let config = await serviceContainer.configurationService.getConfiguration()
        let value = config?.analytics.liveMetricsEnabled ?? SDKConstants.ConfigurationDefaults.enableLiveMetrics
        logger.info("📊 Enable live metrics retrieved: \(value)")
        return value
    }

    // MARK: - Analytics Query APIs (Internal)

    /// Get analytics for a specific session
    internal func getAnalyticsSession(_ sessionId: UUID) async -> GenerationSession? {
        logger.info("📊 Getting analytics session: \(sessionId)")
        let analytics = await serviceContainer.generationAnalytics
        return await analytics.getSession(sessionId)
    }

    /// Get all generations for a session
    internal func getGenerationsForSession(_ sessionId: UUID) async -> [Generation] {
        logger.info("📊 Getting generations for session: \(sessionId)")
        let analytics = await serviceContainer.generationAnalytics
        return await analytics.getGenerations(for: sessionId)
    }

    /// Get all analytics sessions
    internal func getAllAnalyticsSessions() async -> [GenerationSession] {
        logger.info("📊 Getting all analytics sessions")
        let analytics = await serviceContainer.generationAnalytics
        return await analytics.getAllSessions()
    }

    /// Get session summary with aggregated metrics
    internal func getSessionSummary(_ sessionId: UUID) async -> SessionSummary? {
        logger.info("📊 Getting session summary: \(sessionId)")
        let analytics = await serviceContainer.generationAnalytics
        return await analytics.getSessionSummary(sessionId)
    }

    /// Get average metrics for a model
    internal func getAverageMetrics(for modelId: String, limit: Int = 100) async -> AverageMetrics? {
        logger.info("📊 Getting average metrics for model: \(modelId)")
        let analytics = await serviceContainer.generationAnalytics
        return await analytics.getAverageMetrics(for: modelId, limit: limit)
    }

    /// Observe live metrics for a generation
    internal func observeLiveMetrics(for generationId: UUID) -> AsyncStream<LiveGenerationMetrics> {
        logger.info("📊 Observing live metrics for generation: \(generationId)")
        let analytics = Task {
            await serviceContainer.generationAnalytics
        }

        return AsyncStream { continuation in
            Task {
                let analyticsService = await analytics.value
                for await metrics in await analyticsService.observeLiveMetrics(for: generationId) {
                    continuation.yield(metrics)
                }
                continuation.finish()
            }
        }
    }

    /// Get current active session ID (if any)
    internal func getCurrentSessionId() async -> UUID? {
        logger.info("📊 Getting current session ID")
        let analytics = await serviceContainer.generationAnalytics
        return await analytics.getCurrentSessionId()
    }


    // MARK: - Private Methods

    private func setupServices() {
        // Services will be registered in the ServiceContainer
    }
}

// MARK: - Performance and Testing Access

extension RunAnywhereSDK {
    /// Access to performance monitoring
    public var performanceMonitor: PerformanceMonitor {
        serviceContainer.performanceMonitor
    }

    /// Access to benchmarking
    public var benchmarkSuite: BenchmarkRunner {
        serviceContainer.benchmarkRunner
    }

    /// Access to A/B testing
    public var abTesting: ABTestRunner {
        serviceContainer.abTestRunner
    }

    /// Access to generation analytics service for advanced use cases
    internal var generationAnalytics: GenerationAnalyticsService {
        get async {
            await serviceContainer.generationAnalytics
        }
    }
}

// MARK: - Storage Management

extension RunAnywhereSDK {
    /// Get storage information
    /// - Returns: Storage information including app, device, and model storage details
    public func getStorageInfo() async -> StorageInfo {
        let totalSize = serviceContainer.fileManager.getTotalStorageSize()
        let availableSpace = serviceContainer.fileManager.getAvailableSpace()
        let modelStorageSize = serviceContainer.fileManager.getModelStorageSize()

        // Get stored models for detailed info
        let storedModels = await getStoredModels()

        // Group models by framework
        var modelsByFramework: [LLMFramework: [StoredModel]] = [:]
        for model in storedModels {
            if let framework = model.framework {
                if modelsByFramework[framework] == nil {
                    modelsByFramework[framework] = []
                }
                modelsByFramework[framework]?.append(model)
            }
        }

        // Find largest model
        let largestModel = storedModels.max { $0.size < $1.size }

        return StorageInfo(
            appStorage: AppStorageInfo(
                documentsSize: totalSize,
                cacheSize: 0, // Could be enhanced to track cache separately
                appSupportSize: 0,
                totalSize: totalSize
            ),
            deviceStorage: DeviceStorageInfo(
                totalSpace: availableSpace + totalSize, // Approximate
                freeSpace: availableSpace,
                usedSpace: totalSize
            ),
            modelStorage: ModelStorageInfo(
                totalSize: modelStorageSize,
                modelCount: storedModels.count,
                modelsByFramework: modelsByFramework,
                largestModel: largestModel
            ),
            cacheSize: 0, // Could be enhanced to track cache separately
            storedModels: storedModels,
            lastUpdated: Date()
        )
    }

    /// Get all stored models with their metadata
    /// - Returns: Array of stored model information
    public func getStoredModels() async -> [StoredModel] {
        // Get basic model info from file system
        let modelData = serviceContainer.fileManager.getAllStoredModels()

        // Get metadata from repository if available
        let repositoryModels: [ModelInfo]
        do {
            repositoryModels = try await listAvailableModels()
        } catch {
            repositoryModels = []
        }

        // Map to StoredModel
        return modelData.compactMap { modelId, format, size in
            // Find matching model info from repository
            let modelInfo = repositoryModels.first { $0.id == modelId }

            // Try to construct the model path
            let baseURL = serviceContainer.fileManager.getBaseDirectoryURL()
            let modelsURL = baseURL.appendingPathComponent("Models")

            // Detect framework
            let framework = modelInfo?.compatibleFrameworks.first ?? detectFramework(for: format)

            // Determine path based on framework
            var modelPath: URL
            if let framework = framework {
                modelPath = modelsURL
                    .appendingPathComponent(framework.rawValue)
                    .appendingPathComponent(modelId)
                    .appendingPathComponent("\(modelId).\(format.rawValue)")
            } else {
                modelPath = modelsURL
                    .appendingPathComponent(modelId)
                    .appendingPathComponent("\(modelId).\(format.rawValue)")
            }

            return StoredModel(
                name: modelInfo?.name ?? modelId,
                path: modelPath,
                size: size,
                format: format,
                framework: framework,
                createdDate: Date(), // Could be enhanced to get actual creation date
                lastUsed: nil, // Could be enhanced with usage tracking
                metadata: modelInfo?.metadata,
                contextLength: modelInfo?.contextLength,
                checksum: modelInfo?.checksum
            )
        }
    }

    /// Clear all cache files
    public func clearCache() async throws {
        try serviceContainer.fileManager.clearCache()
    }

    /// Clean temporary files
    public func cleanTempFiles() async throws {
        try serviceContainer.fileManager.cleanTempFiles()
    }

    /// Delete a specific model
    /// - Parameter modelId: The model ID to delete
    public func deleteStoredModel(_ modelId: String) async throws {
        try serviceContainer.fileManager.deleteModel(modelId: modelId)
    }

    /// Get the base storage directory URL
    /// - Returns: URL to the base RunAnywhere directory
    public func getBaseDirectoryURL() -> URL {
        return serviceContainer.fileManager.getBaseDirectoryURL()
    }

    // MARK: - Private Helpers

    private func detectFramework(for format: ModelFormat) -> LLMFramework? {
        switch format {
        case .gguf, .ggml:
            return .llamaCpp
        case .mlmodel, .mlpackage:
            return .coreML
        case .onnx:
            return .onnx
        case .tflite:
            return .tensorFlowLite
        case .mlx:
            return .mlx
        default:
            return nil
        }
    }
}
