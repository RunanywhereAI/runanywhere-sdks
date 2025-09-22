import Foundation
import Combine
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
    private static let logger = SDKLogger(category: "RunAnywhere")

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

    /// Initialize network services (API client, authentication) for the SDK
    /// Call this after SDK initialization to enable backend connectivity
    public static func initializeNetworkServices() async throws {
        guard isInitialized else {
            throw SDKError.notInitialized("SDK must be initialized before initializing network services")
        }

        guard let params = initParams else {
            throw SDKError.notInitialized("SDK initialization parameters are missing")
        }

        if params.environment != .development {
            try await serviceContainer.initializeNetworkServices(with: params)
        }
    }

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
        guard !isInitialized else { return }

        let logger = SDKLogger(category: "RunAnywhere.Init")
        EventBus.shared.publish(SDKInitializationEvent.started)

        do {
            // Step 1: Validate API key (skip in development mode)
            if params.environment != .development {
                guard !params.apiKey.isEmpty else {
                    throw SDKError.invalidAPIKey("API key cannot be empty")
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

        } catch {
            logger.error("❌ SDK initialization failed: \(error.localizedDescription)")
            configurationData = nil
            initParams = nil
            isInitialized = false
            EventBus.shared.publish(SDKInitializationEvent.failed(error))
            throw error
        }
    }

    // MARK: - Lazy Device Registration

    /// Track device registration state (self-contained implementation)
    private static var _cachedDeviceId: String?
    private static var _isRegistering: Bool = false
    private static let registrationLock = NSLock()

    /// Ensure device is registered with backend (lazy registration)
    /// Only registers if device ID doesn't exist locally
    /// - Throws: SDKError if registration fails
    internal static func ensureDeviceRegistered() async throws {
        registrationLock.lock()

        // Check if we're already registering
        if _isRegistering {
            registrationLock.unlock()
            // Wait for registration to complete
            while _isRegistering {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            return
        }

        // Check if we have a cached device ID
        if let cachedId = _cachedDeviceId, !cachedId.isEmpty {
            registrationLock.unlock()
            return
        }

        // Check if device is already registered in local storage
        if let storedDeviceId = getStoredDeviceId(), !storedDeviceId.isEmpty {
            _cachedDeviceId = storedDeviceId
            registrationLock.unlock()
            return
        }

        // Mark as registering
        _isRegistering = true
        registrationLock.unlock()

        let logger = SDKLogger(category: "RunAnywhere.Registration")
        logger.info("Starting device registration...")

        do {
            // Skip registration in development mode
            if currentEnvironment == .development {
                let mockDeviceId = "dev-" + generateDeviceIdentifier()
                try storeDeviceId(mockDeviceId)
                _cachedDeviceId = mockDeviceId
                logger.info("Using mock device ID for development: \(mockDeviceId.prefix(8))...")
                _isRegistering = false
                return
            }

            // Ensure we have network services initialized
            guard let params = initParams else {
                throw SDKError.notInitialized("SDK initialization parameters are missing for device registration")
            }

            // Initialize API client and auth service if needed
            if serviceContainer.authenticationService == nil {
                print("🔧 DeviceRegistration: Initializing network services...")
                try await serviceContainer.initializeNetworkServices(with: params)
                print("✅ DeviceRegistration: Network services initialized")
            }

            guard let authService = serviceContainer.authenticationService else {
                throw SDKError.invalidState("Authentication service not available")
            }

            // Register device with backend
            let deviceRegistration = try await authService.registerDevice()

            // Store device ID locally
            try storeDeviceId(deviceRegistration.deviceId)
            _cachedDeviceId = deviceRegistration.deviceId

            logger.info("Device registered successfully: \(deviceRegistration.deviceId.prefix(8))...")

        } catch {
            logger.error("Device registration failed: \(error.localizedDescription)")
            _isRegistering = false
            throw error
        }

        // Mark registration as complete
        _isRegistering = false
        logger.debug("Device registration completed")
    }

    // MARK: - Device ID Management

    private static let deviceIdKey = "com.runanywhere.sdk.deviceId"

    /// Get stored device ID from local persistence
    private static func getStoredDeviceId() -> String? {
        // Try keychain first (production), then UserDefaults (development)
        if let keychainId = KeychainManager.shared.retrieveDeviceUUID() {
            return keychainId
        }

        // Fallback to UserDefaults
        return UserDefaults.standard.string(forKey: deviceIdKey)
    }

    /// Store device ID in local persistence
    private static func storeDeviceId(_ deviceId: String) throws {
        guard !deviceId.isEmpty else {
            throw SDKError.validationFailed("Device ID cannot be empty")
        }

        // Store in keychain for production environments
        if let environment = currentEnvironment, environment != .development {
            try KeychainManager.shared.storeDeviceUUID(deviceId)
        }

        // Always store in UserDefaults as fallback
        UserDefaults.standard.set(deviceId, forKey: deviceIdKey)
        UserDefaults.standard.synchronize()
    }

    /// Clear stored device ID
    private static func clearStoredDeviceId() {
        // Clear from keychain using the deviceUUID key
        try? KeychainManager.shared.delete(for: "com.runanywhere.sdk.device.uuid")

        // Clear from UserDefaults
        UserDefaults.standard.removeObject(forKey: deviceIdKey)
        UserDefaults.standard.synchronize()

        // Clear cache
        _cachedDeviceId = nil
    }

    /// Generate a unique device identifier
    private static func generateDeviceIdentifier() -> String {
        #if os(iOS) || os(tvOS) || os(watchOS)
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString {
            return vendorId
        }
        #endif

        // Fallback to random UUID
        return UUID().uuidString
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
                throw SDKError.notInitialized("SDK must be initialized before generating text")
            }

            // Lazy device registration on first API call
            try await ensureDeviceRegistered()

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
                        throw SDKError.notInitialized("SDK must be initialized before streaming text generation")
                    }

                    // Lazy device registration on first API call
                    try await ensureDeviceRegistered()

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
                throw SDKError.notInitialized("SDK must be initialized before generating structured output")
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
                throw SDKError.notInitialized("SDK must be initialized before transcribing audio")
            }

            // Lazy device registration on first API call
            try await ensureDeviceRegistered()

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
                throw SDKError.notInitialized("SDK must be initialized before loading models")
            }

            // Lazy device registration on first API call
            try await ensureDeviceRegistered()

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
            throw SDKError.notInitialized("SDK must be initialized before retrieving available models")
        }

        // Use print statements for debugging since logger isn't working
        print("📍 RunAnywhere.availableModels() called")
        print("🔐 Device registered: \(isDeviceRegistered())")
        print("🌐 API Client available: \(serviceContainer.apiClient != nil)")

        logger.info("📍 RunAnywhere.availableModels() called")
        logger.info("🔐 Device registered: \(isDeviceRegistered())")
        logger.info("🌐 API Client available: \(serviceContainer.apiClient != nil)")

        // Use model registry to get available models
        print("🔍 Calling modelRegistry.discoverModels()...")
        logger.info("🔍 Calling modelRegistry.discoverModels()...")
        let models = await serviceContainer.modelRegistry.discoverModels()
        print("📊 ModelRegistry returned \(models.count) models")
        logger.info("📊 ModelRegistry returned \(models.count) models")
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

    // MARK: - Authentication Info

    /// Get current user ID
    public static func getUserId() async -> String? {
        guard isInitialized,
              let authService = serviceContainer.authenticationService else {
            return nil
        }
        return await authService.getUserId()
    }

    /// Get current organization ID
    public static func getOrganizationId() async -> String? {
        guard isInitialized,
              let authService = serviceContainer.authenticationService else {
            return nil
        }
        return await authService.getOrganizationId()
    }

    /// Get current device ID
    public static func getDeviceId() async -> String? {
        guard isInitialized else {
            return nil
        }

        // Try to get from local storage first
        if let deviceId = getStoredDeviceId() {
            return deviceId
        }

        // Fallback to auth service if available
        if let authService = serviceContainer.authenticationService {
            return await authService.getDeviceId()
        }

        return nil
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

        // Clear device registration
        clearStoredDeviceId()

        // Reset service container if needed
        serviceContainer.reset()

        logger.info("SDK state reset completed")
    }

    /// Get current SDK version
    /// - Returns: SDK version string
    public static func getSDKVersion() -> String {
        return "1.0.0" // TODO: Get from build configuration
    }

    /// Get current environment
    /// - Returns: Current SDK environment
    public static func getCurrentEnvironment() -> SDKEnvironment? {
        return currentEnvironment
    }

    /// Check if device is registered
    /// - Returns: true if device has been registered with backend
    public static func isDeviceRegistered() -> Bool {
        return getStoredDeviceId() != nil
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
