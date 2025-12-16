import Combine
import Foundation
#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#endif

/// The clean, event-based RunAnywhere SDK
/// Single entry point with both event-driven and async/await patterns
public enum RunAnywhere {

    // MARK: - Internal State Management

    /// Internal configuration storage
    internal static var configurationData: ConfigurationData?
    internal static var initParams: SDKInitParams?
    internal static var currentEnvironment: SDKEnvironment?
    private static var isInitialized = false

    /// Track if network bootstrap is complete (makes ensureDeviceRegistered O(1) after first call)
    private static var isBootstrapped = false

    /// Access to service container (through the shared instance for now)
    internal static var serviceContainer: ServiceContainer {
        ServiceContainer.shared
    }

    /// Check if SDK is initialized
    public static var isSDKInitialized: Bool {
        isInitialized
    }

    // MARK: - Event Access

    /// Access to all SDK events for subscription-based patterns
    public static var events: EventBus {
        EventBus.shared
    }

    // MARK: - SDK Initialization

    /**
     * Initialize the RunAnywhere SDK
     *
     * This method performs simple, fast initialization with no network calls:
     *
     * 1. **Validation**: Validate API key and parameters
     * 2. **Logging**: Initialize logging system based on environment
     * 3. **Storage**: Store parameters locally (no keychain for dev mode)
     * 4. **State**: Mark SDK as initialized
     *
     * NO network calls, NO device registration, NO complex bootstrapping.
     * Device registration happens lazily on first API call.
     *
     * - Parameters:
     *   - apiKey: Your RunAnywhere API key from the console
     *   - baseURL: Backend API base URL
     *   - environment: SDK environment (development/staging/production)
     *
     * - Throws: SDKError if validation fails
     */
    public static func initialize(
        apiKey: String,
        baseURL: URL,
        environment: SDKEnvironment = .production
    ) throws {
        let params = SDKInitParams(apiKey: apiKey, baseURL: baseURL, environment: environment)
        try initialize(with: params)
    }

    /// Initialize the SDK with string URL
    /// - Parameters:
    ///   - apiKey: Your RunAnywhere API key
    ///   - baseURL: Base URL string for API requests
    ///   - environment: Environment mode (default: production)
    public static func initialize(
        apiKey: String,
        baseURL: String,
        environment: SDKEnvironment = .production
    ) throws {
        let params = try SDKInitParams(apiKey: apiKey, baseURL: baseURL, environment: environment)
        try initialize(with: params)
    }

    /// Initialize the SDK with parameters
    /// - Parameter params: SDK initialization parameters
    private static func initialize(with params: SDKInitParams) throws {
        // Return early if already initialized
        guard !isInitialized else {
            return
        }

        let logger = SDKLogger(category: "RunAnywhere.Init")

        // Dispatch SDK init started event
        EventPublisher.shared.track(SDKLifecycleEvent.initStarted)

        do {
            // Step 1: Validate API key (skip in development mode)
            if params.environment != .development {
                guard !params.apiKey.isEmpty else {
                    throw RunAnywhereError.invalidAPIKey("API key cannot be empty")
                }
            }

            // Step 2: Initialize logging system
            RunAnywhere.setLogLevel(params.environment.defaultLogLevel)

            // Step 3: Store parameters locally
            initParams = params
            currentEnvironment = params.environment

            // Only store in keychain for non-development environments
            if params.environment != .development {
                try KeychainManager.shared.storeSDKParams(params)
            }

            // Step 4: Initialize database (keep this as it's local only)
            try DatabaseManager.shared.setup()

            // Step 5: Services are lazily initialized when first accessed
            // No additional setup needed here

            // Mark as initialized
            isInitialized = true

            logger.info("✅ SDK initialization completed successfully (\(params.environment.description) mode)")

            // Dispatch SDK init completed event
            EventPublisher.shared.track(SDKLifecycleEvent.initCompleted(durationMs: 0))

            // Step 6: Device registration (after marking as initialized)
            // For development mode: Register immediately with Supabase for dev analytics
            // For production/staging: Lazy registration on first API call
            if params.environment == .development {
                logger.debug("Development mode - triggering device registration!")

                // Trigger device registration in background (non-blocking)
                // Note: ensureDeviceRegistered() checks if already registered and skips if so
                Task.detached(priority: .userInitiated) {
                    do {
                        try await ensureDeviceRegistered()
                        SDKLogger(category: "RunAnywhere.Init").info("✅ Device registered successfully with Supabase")
                    } catch {
                        SDKLogger(category: "RunAnywhere.Init").warning("⚠️ Device registration failed (non-critical): \(error.localizedDescription)")
                        // Don't fail SDK initialization if device registration fails
                    }
                }
            }

        } catch {
            logger.error("❌ SDK initialization failed: \(error.localizedDescription)")
            configurationData = nil
            initParams = nil
            isInitialized = false

            // Dispatch SDK init failed event
            EventPublisher.shared.track(SDKLifecycleEvent.initFailed(error: error.localizedDescription))

            throw error
        }
    }

    // MARK: - Device Registration (Direct Service Orchestration)

    /// Container for core services during initialization
    private struct CoreServices {
        let syncCoordinator: SyncCoordinator
        let configService: ConfigurationService
        let telemetryRepo: TelemetryRepositoryImpl
        let modelInfoService: ModelInfoService
    }

    /// Ensure device is registered with backend (lazy registration)
    /// Orchestrates service initialization directly
    /// Note: This is O(1) after first successful call due to isBootstrapped flag
    internal static func ensureDeviceRegistered() async throws {
        // Fast path: already bootstrapped, return immediately (O(1))
        if isBootstrapped {
            return
        }

        guard let params = initParams, let environment = currentEnvironment else {
            throw RunAnywhereError.notInitialized
        }

        let logger = SDKLogger(category: "RunAnywhere.Bootstrap")

        // Initialize services based on environment
        if environment != .development && serviceContainer.authenticationService == nil {
            try await initializeProductionServices(params: params, environment: environment, logger: logger)
        } else if environment == .development && serviceContainer.networkService == nil {
            try await initializeDevelopmentServices(params: params, logger: logger)
        }

        // Now perform actual device registration
        try await serviceContainer.deviceRegistrationService.ensureDeviceRegistered(
            params: params,
            environment: environment,
            serviceContainer: serviceContainer
        )

        // Mark bootstrap as complete - subsequent calls will be O(1)
        isBootstrapped = true
    }

    /// Initialize production/staging services
    private static func initializeProductionServices(
        params: SDKInitParams,
        environment: SDKEnvironment,
        logger: SDKLogger
    ) async throws {
        logger.info("Initializing network and authentication services...")

        // Setup network and authentication
        let (networkService, apiClient, _) = try await setupNetworkAndAuthentication(
            params: params,
            environment: environment,
            logger: logger
        )

        // Create and inject core services
        let coreServices = try await setupCoreServices(
            apiClient: apiClient,
            networkService: networkService,
            logger: logger
        )

        // Load configuration and models
        try await loadConfigurationAndModels(
            configService: coreServices.configService,
            modelInfoService: coreServices.modelInfoService,
            apiKey: params.apiKey,
            logger: logger
        )

        // Initialize analytics
        try await initializeAnalytics(
            telemetryRepository: coreServices.telemetryRepo,
            apiKey: params.apiKey,
            logger: logger
        )

        logger.info("✅ Production/staging bootstrap completed")
    }

    /// Initialize development mode services
    private static func initializeDevelopmentServices(
        params: SDKInitParams,
        logger: SDKLogger
    ) async throws {
        logger.info("Initializing development mode services (full service stack)...")

        // Setup network service and API client for development
        let networkService = NetworkServiceFactory.createNetworkService(for: .development, params: params)
        serviceContainer.networkService = networkService

        let apiClient = networkService as? APIClient
        serviceContainer.apiClient = apiClient
        logger.debug("Network service and API client initialized (development mode)")

        // Create and inject core services
        let coreServices = try await setupCoreServices(
            apiClient: apiClient,
            networkService: networkService,
            logger: logger
        )

        // Load configuration and models
        try await loadConfigurationAndModels(
            configService: coreServices.configService,
            modelInfoService: coreServices.modelInfoService,
            apiKey: params.apiKey,
            logger: logger
        )

        // Initialize analytics
        try await initializeAnalytics(
            telemetryRepository: coreServices.telemetryRepo,
            apiKey: params.apiKey,
            logger: logger
        )

        logger.info("✅ Development mode bootstrap completed (all services active)")
    }

    /// Setup network service and authentication
    private static func setupNetworkAndAuthentication(
        params: SDKInitParams,
        environment: SDKEnvironment,
        logger: SDKLogger
    ) async throws -> (NetworkService, APIClient, AuthenticationService) {
        // Setup network service
        let networkService = NetworkServiceFactory.createNetworkService(for: environment, params: params)
        serviceContainer.networkService = networkService
        logger.debug("Network service configured for \(environment.description)")

        // Create API client and authentication service
        let (apiClient, authService) = try await AuthenticationService.createAndAuthenticate(
            baseURL: params.baseURL,
            apiKey: params.apiKey
        )
        serviceContainer.authenticationService = authService
        serviceContainer.apiClient = apiClient
        logger.info("Authentication successful")

        return (networkService, apiClient, authService)
    }

    /// Create and inject core services
    private static func setupCoreServices(
        apiClient: APIClient?,
        networkService: NetworkService,
        logger: SDKLogger
    ) async throws -> CoreServices {
        logger.debug("Creating core services...")

        // Create SyncCoordinator
        let syncCoordinator = SyncCoordinator(enableAutoSync: false)
        serviceContainer.setSyncCoordinator(syncCoordinator)

        // Create ConfigurationService
        let configRepo = ConfigurationRepositoryImpl(
            databaseManager: DatabaseManager.shared,
            apiClient: apiClient
        )
        let configService = ConfigurationService(
            configRepository: configRepo,
            syncCoordinator: syncCoordinator
        )
        serviceContainer.setConfigurationService(configService)

        // Create TelemetryRepository
        let telemetryRepo = TelemetryRepositoryImpl(
            databaseManager: DatabaseManager.shared,
            apiClient: apiClient
        )

        // Create ModelInfoService
        let modelRepo = ModelInfoRepositoryImpl(
            databaseManager: DatabaseManager.shared,
            apiClient: apiClient
        )
        let modelInfoService = ModelInfoService(
            modelInfoRepository: modelRepo,
            syncCoordinator: syncCoordinator
        )
        serviceContainer.setModelInfoService(modelInfoService)

        // Create ModelAssignmentService
        let modelAssignmentService = ModelAssignmentService(
            networkService: networkService,
            modelInfoService: modelInfoService
        )
        serviceContainer.setModelAssignmentService(modelAssignmentService)

        logger.info("Core services created and injected")

        return CoreServices(
            syncCoordinator: syncCoordinator,
            configService: configService,
            telemetryRepo: telemetryRepo,
            modelInfoService: modelInfoService
        )
    }

    /// Load configuration and sync model catalog
    private static func loadConfigurationAndModels(
        configService: ConfigurationService,
        modelInfoService: ModelInfoService,
        apiKey: String,
        logger: SDKLogger
    ) async throws {
        // Load configuration
        let config = await configService.loadConfigurationOnLaunch(apiKey: apiKey)
        EventPublisher.shared.track(SDKLifecycleEvent.configLoaded(source: config.source.rawValue))
        logger.info("Configuration loaded (source: \(config.source))")

        // Sync model catalog
        try? await modelInfoService.syncModelInfo()
        _ = try? await modelInfoService.loadStoredModels()
        logger.debug("Model catalog synced")
    }

    /// Initialize analytics and event publisher
    private static func initializeAnalytics(
        telemetryRepository: TelemetryRepositoryImpl,
        apiKey: String,
        logger: SDKLogger
    ) async throws {
        // Initialize model registry
        await (serviceContainer.modelRegistry as? RegistryService)?.initialize(with: apiKey)
        logger.debug("Model registry initialized")

        // Initialize analytics and event publisher
        await serviceContainer.analyticsQueueManager.initialize(telemetryRepository: telemetryRepository)
        EventPublisher.shared.initialize(analyticsQueue: serviceContainer.analyticsQueueManager)
        logger.info("Analytics and event publisher initialized")
    }

    // MARK: - Analytics Submission (Delegated to Service)

    /// Submit generation analytics (public API)
    /// - Note: Only submits in development mode; fails silently on errors
    public static func submitGenerationAnalytics(
        generationId: String,
        modelId: String,
        latencyMs: Double,
        tokensPerSecond: Double,
        inputTokens: Int,
        outputTokens: Int,
        success: Bool
    ) async {
        guard let params = initParams else { return }

        let analyticsParams = GenerationAnalyticsParams(
            generationId: generationId,
            modelId: modelId,
            latencyMs: latencyMs,
            tokensPerSecond: tokensPerSecond,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            success: success
        )

        await serviceContainer.devAnalyticsService.submit(
            analyticsParams: analyticsParams,
            serviceContainer: serviceContainer,
            sdkParams: params
        )
    }

    // MARK: - Text Generation (Clean Async/Await Interface)

    /// Simple text generation with automatic event publishing
    /// - Parameter prompt: The text prompt
    /// - Returns: Generated response (text only)
    public static func chat(_ prompt: String) async throws -> String {
        let result = try await generate(prompt, options: nil)
        return result.text
    }

    /// Generate text with full metrics and analytics
    /// - Parameters:
    ///   - prompt: The text prompt
    ///   - options: Generation options (optional)
    /// - Returns: GenerationResult with full metrics including thinking tokens, timing, performance, etc.
    /// - Note: Events are automatically dispatched to both EventBus and Analytics
    public static func generate(
        _ prompt: String,
        options: LLMGenerationOptions? = nil
    ) async throws -> LLMGenerationResult {
        // Ensure initialized
        guard isInitialized else {
            throw RunAnywhereError.notInitialized
        }

        // Lazy device registration on first API call (O(1) after first call)
        try await ensureDeviceRegistered()

        // LLMCapability handles all event tracking automatically
        return try await serviceContainer.llmCapability.generate(
            prompt,
            options: options ?? LLMGenerationOptions()
        )
    }

    /// Streaming text generation with complete analytics
    ///
    /// Returns both a token stream for real-time display and a task that resolves to complete metrics.
    ///
    /// Example usage:
    /// ```swift
    /// let result = try await RunAnywhere.generateStream(prompt)
    ///
    /// // Display tokens in real-time
    /// for try await token in result.stream {
    ///     print(token, terminator: "")
    /// }
    ///
    /// // Get complete analytics after streaming finishes
    /// let metrics = try await result.result.value
    /// print("Speed: \(metrics.performanceMetrics.tokensPerSecond) tok/s")
    /// print("Tokens: \(metrics.tokensUsed)")
    /// print("Time: \(metrics.latencyMs)ms")
    /// ```
    ///
    /// - Parameters:
    ///   - prompt: The text prompt
    ///   - options: Generation options (optional)
    /// - Returns: StreamingResult containing both the token stream and final metrics task
    public static func generateStream(
        _ prompt: String,
        options: LLMGenerationOptions? = nil
    ) async throws -> LLMStreamingResult {
        // Ensure initialized
        guard isInitialized else {
            throw RunAnywhereError.notInitialized
        }

        // Lazy device registration on first API call (O(1) after first call)
        try await ensureDeviceRegistered()

        // LLMCapability handles all event tracking automatically
        return try await serviceContainer.llmCapability.generateStream(
            prompt,
            options: options ?? LLMGenerationOptions()
        )
    }

    // MARK: - Voice Operations

    /// Simple voice transcription using default model
    /// - Parameter audioData: Audio data to transcribe
    /// - Returns: Transcribed text
    /// - Note: Events are automatically dispatched to both EventBus and Analytics
    public static func transcribe(_ audioData: Data) async throws -> String {
        guard isInitialized else { throw RunAnywhereError.notInitialized }
        try await ensureDeviceRegistered()

        // STTCapability handles all event tracking automatically
        let result = try await serviceContainer.sttCapability.transcribe(audioData)
        return result.text
    }

    // MARK: - Model Management

    /// Load an LLM model by ID
    /// - Parameter modelId: The model identifier
    /// - Note: Events are automatically dispatched to both EventBus (for apps) and Analytics (for telemetry)
    public static func loadModel(_ modelId: String) async throws {
        // Ensure initialized
        guard isInitialized else {
            throw RunAnywhereError.notInitialized
        }

        // Lazy device registration on first API call
        try await ensureDeviceRegistered()

        // LLMCapability handles all event tracking automatically
        try await serviceContainer.llmCapability.loadModel(modelId)
    }

    /// Unload the currently loaded LLM model
    /// - Note: Events are automatically dispatched to both EventBus and Analytics
    public static func unloadModel() async throws {
        guard isInitialized else {
            throw RunAnywhereError.notInitialized
        }

        // LLMCapability handles all event tracking automatically
        try await serviceContainer.llmCapability.unload()
    }

    /// Check if an LLM model is loaded
    public static var isModelLoaded: Bool {
        get async {
            await serviceContainer.llmCapability.isModelLoaded
        }
    }

    /// Check if the currently loaded LLM model supports streaming generation
    ///
    /// Some models (like Apple Foundation Models) don't support streaming and require
    /// non-streaming generation via `generate()` instead of `generateStream()`.
    ///
    /// - Returns: `true` if streaming is supported, `false` if you should use `generate()` instead
    /// - Note: Returns `false` if no model is loaded
    public static var supportsLLMStreaming: Bool {
        get async {
            await serviceContainer.llmCapability.supportsStreaming
        }
    }

    /// Load an STT (Speech-to-Text) model by ID
    /// This loads the model into the STT capability
    /// - Parameter modelId: The model identifier (e.g., "whisper-base")
    /// - Note: Events are automatically dispatched to both EventBus and Analytics
    public static func loadSTTModel(_ modelId: String) async throws {
        // Ensure initialized
        guard isInitialized else {
            throw RunAnywhereError.notInitialized
        }

        // Lazy device registration on first API call
        try await ensureDeviceRegistered()

        // STTCapability handles all event tracking automatically
        try await serviceContainer.sttCapability.loadModel(modelId)
    }

    /// Load a TTS (Text-to-Speech) voice by ID
    /// This loads the voice into the TTS capability
    /// - Parameter voiceId: The voice identifier
    /// - Note: Events are automatically dispatched to both EventBus and Analytics
    public static func loadTTSModel(_ voiceId: String) async throws {
        // Ensure initialized
        guard isInitialized else {
            throw RunAnywhereError.notInitialized
        }

        // Lazy device registration on first API call
        try await ensureDeviceRegistered()

        // TTSCapability handles all event tracking automatically
        try await serviceContainer.ttsCapability.loadVoice(voiceId)
    }

    /// Get available models
    /// - Returns: Array of available models
    public static func availableModels() async throws -> [ModelInfo] {
        guard isInitialized else { throw RunAnywhereError.notInitialized }
        return await serviceContainer.modelRegistry.discoverModels()
    }

    /// Get currently loaded LLM model ID
    /// - Returns: Currently loaded model ID if any
    public static func getCurrentModelId() async -> String? {
        guard isInitialized else { return nil }
        return await serviceContainer.llmCapability.currentModelId
    }

    /// Get the currently loaded LLM model as ModelInfo
    ///
    /// This is a convenience property that combines `getCurrentModelId()` with
    /// a lookup in the available models registry.
    ///
    /// - Returns: The currently loaded ModelInfo, or nil if no model is loaded
    public static var currentLLMModel: ModelInfo? {
        get async {
            guard let modelId = await getCurrentModelId() else { return nil }
            let models = (try? await availableModels()) ?? []
            return models.first { $0.id == modelId }
        }
    }

    /// Get the currently loaded STT model as ModelInfo
    ///
    /// - Returns: The currently loaded STT ModelInfo, or nil if no STT model is loaded
    public static var currentSTTModel: ModelInfo? {
        get async {
            guard isInitialized else { return nil }
            guard let modelId = await serviceContainer.sttCapability.currentModelId else { return nil }
            let models = (try? await availableModels()) ?? []
            return models.first { $0.id == modelId }
        }
    }

    /// Get the currently loaded TTS voice ID
    ///
    /// Note: TTS uses voices (not models), so this returns the voice identifier string.
    /// - Returns: The TTS voice ID if one is loaded, nil otherwise
    public static var currentTTSVoiceId: String? {
        get async {
            guard isInitialized else { return nil }
            return await serviceContainer.ttsCapability.currentVoiceId
        }
    }

    /// Cancel the current text generation
    ///
    /// Use this to stop an ongoing generation when the user navigates away
    /// or explicitly requests cancellation.
    public static func cancelGeneration() async {
        guard isInitialized else { return }
        await serviceContainer.llmCapability.cancel()
    }

    // MARK: - Authentication Info

    /// Get current user ID
    /// - Returns: User ID if SDK is initialized and authenticated, nil otherwise
    public static func getUserId() async -> String? {
        guard isInitialized,
              let authService = serviceContainer.authenticationService else {
            return nil
        }
        return await authService.getUserId()
    }

    /// Get current organization ID
    /// - Returns: Organization ID if SDK is initialized and authenticated, nil otherwise
    public static func getOrganizationId() async -> String? {
        guard isInitialized,
              let authService = serviceContainer.authenticationService else {
            return nil
        }
        return await authService.getOrganizationId()
    }

    /// Get current device ID
    public static func getDeviceId() async -> String? {
        guard isInitialized else { return nil }
        return await serviceContainer.deviceRegistrationService.getDeviceId()
    }

    // MARK: - SDK State Management

    /// Check if SDK has been initialized
    /// - Returns: true if SDK has been initialized
    public static func hasBeenInitialized() -> Bool {
        return isSDKInitialized
    }

    /// Check if SDK is active and ready for use
    /// - Returns: true if SDK is initialized and has valid configuration
    public static func isActive() -> Bool {
        return hasBeenInitialized() && initParams != nil
    }

    /// Reset SDK state (for testing purposes)
    /// Clears all initialization state and cached data
    public static func reset() {
        let logger = SDKLogger(category: "RunAnywhere.Reset")
        logger.info("Resetting SDK state...")

        // Clear initialization state
        isInitialized = false
        isBootstrapped = false
        initParams = nil
        currentEnvironment = nil
        configurationData = nil

        // Reset service container (includes device registration cleanup)
        serviceContainer.reset()

        logger.info("SDK state reset completed")
    }

    /// Get current SDK version
    /// - Returns: SDK version string
    public static func getSDKVersion() -> String {
        SDKConstants.version
    }

    /// Get current environment
    /// - Returns: Current SDK environment
    public static func getCurrentEnvironment() -> SDKEnvironment? {
        return currentEnvironment
    }

    /// Check if device is registered
    /// - Returns: true if device has been registered with backend
    public static func isDeviceRegistered() async -> Bool {
        return await serviceContainer.deviceRegistrationService.isRegistered()
    }
}

// MARK: - Utilities

extension RunAnywhere {
    /// Estimate token count in text
    ///
    /// Uses simple heuristics (~4 characters per token) for estimation.
    ///
    /// Example:
    /// ```swift
    /// let prompt = "Explain quantum computing"
    /// let tokenCount = RunAnywhere.estimateTokenCount(prompt)
    /// print("Estimated tokens: \(tokenCount)")
    /// ```
    ///
    /// - Parameter text: The text to analyze
    /// - Returns: Estimated number of tokens
    public static func estimateTokenCount(_ text: String) -> Int {
        // Simple estimation: ~4 characters per token on average
        return max(1, text.count / 4)
    }
}
