// swiftlint:disable file_length
import Combine
import Foundation
#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#endif

/// The clean, event-based RunAnywhere SDK
/// Single entry point with both event-driven and async/await patterns
public enum RunAnywhere { // swiftlint:disable:this type_body_length

    // MARK: - Internal State Management

    /// Internal configuration storage
    internal static var configurationData: ConfigurationData?
    internal static var initParams: SDKInitParams?
    internal static var currentEnvironment: SDKEnvironment?
    private static var isInitialized = false

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
        EventBus.shared.publish(SDKInitializationEvent.started)

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

            // Step 5: Setup local services only (no network calls)
            try serviceContainer.setupLocalServices(with: params)

            // Mark as initialized
            isInitialized = true

            logger.info("✅ SDK initialization completed successfully (\(params.environment.description) mode)")
            EventBus.shared.publish(SDKInitializationEvent.completed)

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
            EventBus.shared.publish(SDKInitializationEvent.failed(error))
            throw error
        }
    }

    // MARK: - Device Registration (Delegated to Service)

    /// Ensure device is registered with backend (lazy registration)
    /// Delegates to DeviceRegistrationService
    private static func ensureDeviceRegistered() async throws {
        guard let params = initParams, let environment = currentEnvironment else {
            throw RunAnywhereError.notInitialized
        }

        try await serviceContainer.deviceRegistrationService.ensureDeviceRegistered(
            params: params,
            environment: environment,
            serviceContainer: serviceContainer
        )
    }

    // MARK: - Analytics Submission (Delegated to Service)

    /// Submit generation analytics (public API)
    /// - Note: Only submits in development mode; fails silently on errors
    public static func submitGenerationAnalytics( // swiftlint:disable:this function_parameter_count
        generationId: String,
        modelId: String,
        latencyMs: Double,
        tokensPerSecond: Double,
        inputTokens: Int,
        outputTokens: Int,
        success: Bool
    ) async {
        guard let params = initParams else { return }

        await serviceContainer.devAnalyticsService.submit(
            generationId: generationId,
            modelId: modelId,
            latencyMs: latencyMs,
            tokensPerSecond: tokensPerSecond,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            success: success,
            serviceContainer: serviceContainer,
            params: params
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

    /// Text generation with options
    /// - Parameters:
    ///   - prompt: The text prompt
    ///   - options: Generation options (optional, defaults to maxTokens: 100)
    /// - Returns: Generated response
    /// Generate text with full metrics and analytics
    /// - Parameters:
    ///   - prompt: The text prompt
    ///   - options: Generation options (optional)
    /// - Returns: GenerationResult with full metrics including thinking tokens, timing, performance, etc.
    public static func generate(
        _ prompt: String,
        options: LLMGenerationOptions? = nil
    ) async throws -> LLMGenerationResult {
        EventBus.shared.publish(SDKGenerationEvent.started(prompt: prompt))

        do {
            // Ensure initialized
            guard isInitialized else {
                throw RunAnywhereError.notInitialized
            }

            // Lazy device registration on first API call
            try await ensureDeviceRegistered()

            // Use options directly or defaults
            let result = try await serviceContainer.generationService.generate(
                prompt: prompt,
                options: options ?? LLMGenerationOptions()
            )

            EventBus.shared.publish(SDKGenerationEvent.completed(
                response: result.text,
                tokensUsed: result.tokensUsed,
                latencyMs: result.latencyMs
            ))

            return result
        } catch {
            EventBus.shared.publish(SDKGenerationEvent.failed(error))
            throw error
        }
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
        EventBus.shared.publish(SDKGenerationEvent.started(prompt: prompt))

        // Ensure initialized
        guard isInitialized else {
            throw RunAnywhereError.notInitialized
        }

        // Lazy device registration on first API call
        try await ensureDeviceRegistered()

        return serviceContainer.streamingService.generateStreamWithMetrics(
            prompt: prompt,
            options: options ?? LLMGenerationOptions()
        )
    }

    // MARK: - Voice Operations

    /// Simple voice transcription using default model
    /// - Parameter audioData: Audio data to transcribe
    /// - Returns: Transcribed text
    /// - Note: For more control over model/options, use `RunAnywhere.transcribe(audio:modelId:options:)` in the Voice extension
    public static func transcribe(_ audioData: Data) async throws -> String {
        guard isInitialized else { throw RunAnywhereError.notInitialized }
        try await ensureDeviceRegistered()

        events.publish(SDKVoiceEvent.transcriptionStarted)

        do {
            let result = try await serviceContainer.voiceOrchestrator.transcribe(audio: audioData)
            events.publish(SDKVoiceEvent.transcriptionFinal(text: result.text))
            return result.text
        } catch {
            events.publish(SDKVoiceEvent.pipelineError(error))
            throw error
        }
    }

    // MARK: - Model Management

    /// Load a model by ID
    /// - Parameter modelId: The model identifier
    public static func loadModel(_ modelId: String) async throws {
        // Ensure initialized
        guard isInitialized else {
            throw RunAnywhereError.notInitialized
        }

        // Lazy device registration on first API call
        try await ensureDeviceRegistered()

        // Delegate to orchestrator which handles lifecycle, telemetry, analytics, and events
        let result = try await serviceContainer.modelLoadingOrchestrator.loadLLMModel(modelId)

        // Set the loaded model in the generation service
        if let loadedModel = result.loadedModel {
            serviceContainer.generationService.setCurrentModel(loadedModel)
        }
    }

    /// Load an STT (Speech-to-Text) model by ID
    /// This initializes the STT component and loads the model into memory
    /// - Parameter modelId: The model identifier
    public static func loadSTTModel(_ modelId: String) async throws {
        // Ensure initialized
        guard isInitialized else {
            throw RunAnywhereError.notInitialized
        }

        // Lazy device registration on first API call
        try await ensureDeviceRegistered()

        // Delegate to orchestrator which handles lifecycle, telemetry, analytics, and events
        let result = try await serviceContainer.modelLoadingOrchestrator.loadSTTModel(modelId)

        // Store the component for later use
        if let sttComponent = result.sttComponent {
            await MainActor.run {
                _loadedSTTComponent = sttComponent
            }
        }
    }

    /// Load a TTS (Text-to-Speech) model by ID
    /// This initializes the TTS component and loads the model into memory
    /// - Parameter modelId: The model identifier (voice name)
    public static func loadTTSModel(_ modelId: String) async throws {
        // Ensure initialized
        guard isInitialized else {
            throw RunAnywhereError.notInitialized
        }

        // Lazy device registration on first API call
        try await ensureDeviceRegistered()

        // Delegate to orchestrator which handles lifecycle, telemetry, analytics, and events
        let result = try await serviceContainer.modelLoadingOrchestrator.loadTTSModel(modelId)

        // Store the component for later use
        if let ttsComponent = result.ttsComponent {
            await MainActor.run {
                _loadedTTSComponent = ttsComponent
            }
        }
    }

    // MARK: - Loaded Component Storage

    @MainActor private static var _loadedSTTComponent: STTComponent?

    @MainActor private static var _loadedTTSComponent: TTSComponent?

    /// Get the currently loaded STT component
    @MainActor public static var loadedSTTComponent: STTComponent? {
        return _loadedSTTComponent
    }

    /// Get the currently loaded TTS component
    @MainActor public static var loadedTTSComponent: TTSComponent? {
        return _loadedTTSComponent
    }

    /// Get available models
    /// - Returns: Array of available models
    public static func availableModels() async throws -> [ModelInfo] {
        guard isInitialized else { throw RunAnywhereError.notInitialized }
        return await serviceContainer.modelRegistry.discoverModels()
    }

    /// Get currently loaded model
    /// - Returns: Currently loaded model info
    public static var currentModel: ModelInfo? {
        guard isInitialized else { return nil }
        return serviceContainer.generationService.getCurrentModel()?.model
    }

    // MARK: - Multi-Adapter Support (NEW)

    /// Register a framework adapter with optional priority
    /// Higher priority adapters are preferred when multiple can handle the same model
    /// - Parameters:
    ///   - adapter: The framework adapter to register
    ///   - priority: Priority level (higher = preferred, default: 100)
    public static func registerFrameworkAdapter(_ adapter: FrameworkAdapter, priority: Int = 100) {
        // Note: Adapter registration can happen before SDK initialization
        // This allows registering adapters during app setup
        serviceContainer.adapterRegistry.register(adapter, priority: priority)
    }

    /// Get all adapters capable of handling a specific model
    /// - Parameter modelId: The model identifier
    /// - Returns: Array of framework types that can handle this model
    public static func availableAdapters(for modelId: String) async -> [LLMFramework] {
        guard isInitialized,
              let model = serviceContainer.modelRegistry.getModel(by: modelId) else { return [] }

        let adapters = await serviceContainer.adapterRegistry.findAllAdapters(for: model)
        return adapters.map(\.framework)
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

// MARK: - Factory Methods

extension RunAnywhere {
    /// Create a new conversation for multi-turn dialogues
    public static func conversation() -> Conversation {
        Conversation()
    }
}

// MARK: - Utilities

extension RunAnywhere {
    /// Estimate token count in text
    ///
    /// Uses improved heuristics for accurate token estimation.
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
        return TokenCounter.estimateTokenCount(text)
    }
}
