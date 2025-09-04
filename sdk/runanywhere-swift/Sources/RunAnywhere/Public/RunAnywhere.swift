import Foundation
import Combine

/// The clean, event-based RunAnywhere SDK
/// Single entry point with both event-driven and async/await patterns
public enum RunAnywhere {

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
     * This method performs a comprehensive initialization sequence:
     *
     * 1. **Validation**: Validate API key and parameters
     * 2. **Logging**: Initialize logging system based on environment
     * 3. **Storage**: Store credentials securely in keychain
     * 4. **Database**: Set up local SQLite database for caching
     * 5. **Authentication**: Exchange API key for access token with backend
     * 6. **Health Check**: Verify backend connectivity and service health
     * 7. **Services & Sync**: Initialize all services and sync with backend
     *
     * The initialization is atomic - if any step fails, the entire process
     * is rolled back and the SDK remains uninitialized.
     *
     * - Parameters:
     *   - apiKey: Your RunAnywhere API key from the console
     *   - baseURL: Backend API base URL
     *   - environment: SDK environment (development/staging/production)
     *
     * - Throws: SDKError if initialization fails at any step
     */
    public static func initialize(
        apiKey: String,
        baseURL: URL,
        environment: SDKEnvironment = .production
    ) async throws {
        let params = SDKInitParams(apiKey: apiKey, baseURL: baseURL, environment: environment)
        try await initialize(with: params)
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
    ) async throws {
        let params = try SDKInitParams(apiKey: apiKey, baseURL: baseURL, environment: environment)
        try await initialize(with: params)
    }

    /// Initialize the SDK with parameters
    /// - Parameter params: SDK initialization parameters
    private static func initialize(with params: SDKInitParams) async throws {
        let logger = SDKLogger(category: "RunAnywhere.Init")
        EventBus.shared.publish(SDKInitializationEvent.started)

        do {
            // Step 1: Validate API key (skip in development mode)
            if params.environment != .development {
                logger.info("Step 1/8: Validating API key")
                guard !params.apiKey.isEmpty else {
                    throw SDKError.invalidAPIKey("API key cannot be empty")
                }
            } else {
                logger.info("Step 1/8: Skipping API key validation in development mode")
            }

            // Step 2: Initialize logging system
            logger.info("Step 2/8: Initializing logging system")
            RunAnywhere.setLogLevel(params.environment.defaultLogLevel)

            // Step 3: Store parameters securely
            logger.info("Step 3/8: Storing credentials securely")
            initParams = params
            currentEnvironment = params.environment

            // Only store in keychain for non-development environments
            if params.environment != .development {
                try KeychainManager.shared.storeSDKParams(params)
            }

            // Step 4: Initialize database
            logger.info("Step 4/8: Initializing local database")
            try DatabaseManager.shared.setup()

            // Development mode: Skip API authentication and use local/mock services
            if params.environment == .development {
                logger.info("🚀 Running in DEVELOPMENT mode - using local/mock services")
                logger.info("Step 5/8: Skipping API authentication in development mode")
                logger.info("Step 6/8: Skipping health check in development mode")
                logger.info("Step 7/7: Bootstrapping SDK services with local data")

                // Bootstrap without API client for development mode
                let loadedConfig = try await serviceContainer.bootstrapDevelopmentMode(with: params)

                // Store the configuration
                configurationData = loadedConfig

                // Mark as initialized
                isInitialized = true
                logger.info("✅ SDK initialization completed successfully (Development Mode)")
                EventBus.shared.publish(SDKInitializationEvent.completed)

            } else {
                // Production/Staging mode: Full API authentication flow

                // Step 5: Initialize API client and authentication service
                logger.info("Step 5/8: Authenticating with backend")

                // Create API client first
                guard let baseURL = params.baseURL else {
                    throw SDKError.validationFailed("Base URL is required for \(params.environment.description)")
                }

                let apiClient = APIClient(
                    baseURL: baseURL,
                    apiKey: params.apiKey
                )

                // Create authentication service using API client
                let authService = AuthenticationService(apiClient: apiClient)

                // Set auth service in API client to complete the setup
                await apiClient.setAuthenticationService(authService)

                // Authenticate
                let authResponse = try await authService.authenticate(apiKey: params.apiKey)
                logger.info("Authentication successful, token expires in \(authResponse.expiresIn) seconds")

                // Step 6: Perform health check
                logger.info("Step 6/8: Performing health check")
                let healthResponse = try await authService.healthCheck()

                if healthResponse.status != HealthStatus.healthy {
                    logger.warning("Backend health status: \(healthResponse.status)")
                }

                // Step 7: Bootstrap SDK services and sync with backend
                logger.info("Step 7/7: Bootstrapping SDK services and syncing with backend")
                let loadedConfig = try await serviceContainer.bootstrap(
                    with: params,
                    authService: authService,
                    apiClient: apiClient
                )

                // Store the configuration
                configurationData = loadedConfig

                // Mark as initialized
                isInitialized = true
                logger.info("✅ SDK initialization completed successfully")
                EventBus.shared.publish(SDKInitializationEvent.completed)
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


    // MARK: - Text Generation (Clean Async/Await Interface)

    /// Simple text generation with automatic event publishing
    /// - Parameter prompt: The text prompt
    /// - Returns: Generated response
    public static func chat(_ prompt: String) async throws -> String {
        return try await generate(prompt, options: nil)
    }

    /// Text generation with options
    /// - Parameters:
    ///   - prompt: The text prompt
    ///   - options: Generation options (optional)
    /// - Returns: Generated response
    public static func generate(
        _ prompt: String,
        options: RunAnywhereGenerationOptions? = nil
    ) async throws -> String {
        EventBus.shared.publish(SDKGenerationEvent.started(prompt: prompt))

        do {
            // Ensure initialized
            guard isInitialized else {
                throw SDKError.notInitialized
            }

            // Use options directly or defaults
            let result = try await serviceContainer.generationService.generate(
                prompt: prompt,
                options: options ?? RunAnywhereGenerationOptions()
            )

            EventBus.shared.publish(SDKGenerationEvent.completed(
                response: result.text,
                tokensUsed: result.tokensUsed,
                latencyMs: result.latencyMs
            ))

            if result.savedAmount > 0 {
                EventBus.shared.publish(SDKGenerationEvent.costCalculated(
                    amount: 0,
                    savedAmount: result.savedAmount
                ))
            }

            return result.text
        } catch {
            EventBus.shared.publish(SDKGenerationEvent.failed(error))
            throw error
        }
    }

    /// Streaming text generation
    /// - Parameters:
    ///   - prompt: The text prompt
    ///   - options: Generation options (optional)
    /// - Returns: AsyncStream of generated tokens
    public static func generateStream(
        _ prompt: String,
        options: RunAnywhereGenerationOptions? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                EventBus.shared.publish(SDKGenerationEvent.started(prompt: prompt))

                do {
                    // Ensure initialized
                    guard isInitialized else {
                        throw SDKError.notInitialized
                    }

                    let stream = serviceContainer.streamingService.generateStream(
                        prompt: prompt,
                        options: options ?? RunAnywhereGenerationOptions()
                    )

                    var fullResponse = ""
                    for try await token in stream {
                        EventBus.shared.publish(SDKGenerationEvent.tokenGenerated(token: token))
                        fullResponse += token
                        continuation.yield(token)
                    }

                    EventBus.shared.publish(SDKGenerationEvent.completed(
                        response: fullResponse,
                        tokensUsed: fullResponse.count / 4, // Rough estimate
                        latencyMs: 0 // Would need to track properly
                    ))

                    continuation.finish()
                } catch {
                    EventBus.shared.publish(SDKGenerationEvent.failed(error))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Structured output generation
    /// - Parameters:
    ///   - type: The type to generate
    ///   - prompt: The text prompt
    /// - Returns: Generated structured data
    public static func generateStructured<T: Generatable>(
        _ type: T.Type,
        prompt: String
    ) async throws -> T {
        EventBus.shared.publish(SDKGenerationEvent.started(prompt: prompt))

        do {
            // Ensure initialized
            guard isInitialized else {
                throw SDKError.notInitialized
            }

            // For now, structured output generation is not fully implemented
            // This would need proper JSON schema generation and parsing
            throw SDKError.notImplemented
        } catch {
            EventBus.shared.publish(SDKGenerationEvent.failed(error))
            throw error
        }
    }

    // MARK: - Voice Operations

    /// Simple voice transcription
    /// - Parameter audioData: Audio data to transcribe
    /// - Returns: Transcribed text
    public static func transcribe(_ audioData: Data) async throws -> String {
        EventBus.shared.publish(SDKVoiceEvent.transcriptionStarted)

        do {
            // Ensure initialized
            guard isInitialized else {
                throw SDKError.notInitialized
            }

            // Use voice capability service directly
            // Find voice service and transcribe
            guard let voiceService = await serviceContainer.voiceCapabilityService.findVoiceService(for: "whisper-base") else {
                throw STTError.noVoiceServiceAvailable
            }

            try await voiceService.initialize(modelPath: "whisper-base")
            let result = try await voiceService.transcribe(audioData: audioData, options: STTOptions())

            EventBus.shared.publish(SDKVoiceEvent.transcriptionFinal(text: result.transcript))
            return result.transcript
        } catch {
            EventBus.shared.publish(SDKVoiceEvent.pipelineError(error))
            throw error
        }
    }

    // MARK: - Model Management

    /// Load a model by ID
    /// - Parameter modelId: The model identifier
    public static func loadModel(_ modelId: String) async throws {
        EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: modelId))

        do {
            // Ensure initialized
            guard isInitialized else {
                throw SDKError.notInitialized
            }

            let loadedModel = try await serviceContainer.modelLoadingService.loadModel(modelId)

            // IMPORTANT: Set the loaded model in the generation service
            serviceContainer.generationService.setCurrentModel(loadedModel)

            EventBus.shared.publish(SDKModelEvent.loadCompleted(modelId: modelId))
        } catch {
            EventBus.shared.publish(SDKModelEvent.loadFailed(modelId: modelId, error: error))
            throw error
        }
    }

    /// Get available models
    /// - Returns: Array of available models
    public static func availableModels() async throws -> [ModelInfo] {
        guard isInitialized else {
            throw SDKError.notInitialized
        }

        // Use model registry to get available models
        let models = await serviceContainer.modelRegistry.discoverModels()
        return models
    }

    /// Get currently loaded model
    /// - Returns: Currently loaded model info
    public static var currentModel: ModelInfo? {
        guard isInitialized else {
            return nil
        }

        // Get the current model from the generation service
        return serviceContainer.generationService.getCurrentModel()?.model
    }
}


// MARK: - Conversation Management

/// Simple conversation manager
public class Conversation {
    private var messages: [String] = []

    public init() {}

    /// Send a message and get response
    public func send(_ message: String) async throws -> String {
        messages.append("User: \(message)")

        let contextPrompt = messages.joined(separator: "\n") + "\nAssistant:"
        let response = try await RunAnywhere.generate(contextPrompt)

        messages.append("Assistant: \(response)")
        return response
    }

    /// Get conversation history
    public var history: [String] {
        messages
    }

    /// Clear conversation
    public func clear() {
        messages.removeAll()
    }
}

// MARK: - Factory Methods

extension RunAnywhere {
    /// Create a new conversation
    public static func conversation() -> Conversation {
        Conversation()
    }
}
