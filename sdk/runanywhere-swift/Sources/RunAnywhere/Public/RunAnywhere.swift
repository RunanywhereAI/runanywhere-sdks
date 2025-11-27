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

    // MARK: - Lazy Device Registration

    /// Actor for managing device registration state in a thread-safe manner
    private actor RegistrationState {
        var cachedDeviceId: String?
        var isRegistering: Bool = false

        func getCachedDeviceId() -> String? {
            return cachedDeviceId
        }

        func setCachedDeviceId(_ deviceId: String?) {
            self.cachedDeviceId = deviceId
        }

        func checkAndSetRegistering() -> Bool {
            if isRegistering {
                return false // Already registering
            }
            isRegistering = true
            return true // Successfully set to registering
        }

        func clearRegistering() {
            isRegistering = false
        }

        func getIsRegistering() -> Bool {
            return isRegistering
        }
    }

    private static let registrationState = RegistrationState()

    /// Maximum number of registration retry attempts
    private static let maxRegistrationRetries = 3
    /// Delay between retry attempts (in nanoseconds)
    private static let retryDelayNanoseconds: UInt64 = 2_000_000_000 // 2 seconds

    /// Ensure device is registered with backend (lazy registration)
    /// Only registers if device ID doesn't exist locally
    /// - Throws: SDKError if registration fails
    private static func ensureDeviceRegistered() async throws {
        let logger = SDKLogger(category: "RunAnywhere.DeviceReg")

        // Check if we have a cached device ID
        let cachedId = await registrationState.getCachedDeviceId()
        if let cachedId = cachedId, !cachedId.isEmpty {
            logger.debug("Device already registered (cached): \(cachedId.prefix(8))...")
            return
        }

        // Check if device is already registered in local storage
        let storedDeviceId = getStoredDeviceId()
        if let storedDeviceId = storedDeviceId, !storedDeviceId.isEmpty {
            logger.debug("Found stored device ID: \(storedDeviceId.prefix(8))...")
            await registrationState.setCachedDeviceId(storedDeviceId)

            // In development mode, still need to check if registered to Supabase
            let isDevRegistered = isDevDeviceRegistered()
            if currentEnvironment == .development && !isDevRegistered {
                logger.debug("Device ID exists but not registered - will register now")
                // Device ID exists but not registered to Supabase yet - continue with registration
            } else {
                logger.debug("Device already fully registered (devRegistered=\(isDevRegistered))")
                // Already fully registered (or not in dev mode)
                return
            }
        } else {
            logger.debug("No device ID found - will create and register")
        }

        // Try to set registering flag - if already registering, wait for completion
        let canRegister = await registrationState.checkAndSetRegistering()
        if !canRegister {
            // Wait for registration to complete with timeout
            var waitAttempts = 0
            let maxWaitAttempts = 50 // 5 seconds total timeout
            while await registrationState.getIsRegistering() && waitAttempts < maxWaitAttempts {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                waitAttempts += 1
            }

            // Check if we have a device ID after waiting
            if let deviceId = await registrationState.getCachedDeviceId(), !deviceId.isEmpty {
                return
            } else if waitAttempts >= maxWaitAttempts {
                throw SDKError.timeout("Device registration timeout")
            }
            return
        }

        logger.debug("Starting device registration...")

        // In development mode, register to Supabase (dev analytics)
        if currentEnvironment == .development {
            logger.debug("Development mode - registering device for dev analytics...")

            do {
                // Call dev registration with Supabase
                // This will throw if registration fails, and will store device ID if it succeeds
                try await registerDevDevice()

                // Get the device ID that was just registered (must exist now)
                guard let deviceId = getStoredDeviceId() else {
                    throw SDKError.storageError("Device ID not found after successful registration")
                }

                await registrationState.setCachedDeviceId(deviceId)

                // Mark as registered ONLY after successful Supabase registration
                markDevDeviceAsRegistered()

                logger.info("✅ Dev device registration successful")
                await registrationState.clearRegistering()
                return
            } catch {
                // Non-critical error - create mock device ID and continue
                logger.warning("Dev device registration failed (non-critical): \(error.localizedDescription)")

                let mockDeviceId = "dev-" + generateDeviceIdentifier()
                do {
                    try storeDeviceId(mockDeviceId)
                    await registrationState.setCachedDeviceId(mockDeviceId)
                    logger.info("Using mock device ID for development: \(mockDeviceId.prefix(8))...")
                    await registrationState.clearRegistering()
                    return
                } catch {
                    logger.error("Failed to store mock device ID: \(error.localizedDescription)")
                    await registrationState.clearRegistering()
                    throw SDKError.storageError("Failed to store device ID: \(error.localizedDescription)")
                }
            }
        }

        // Ensure we have network services initialized
        guard let params = initParams else {
            throw SDKError.notInitialized
        }

        // Registration with retry logic
        var lastError: Error?

        for attempt in 1...maxRegistrationRetries {
            do {
                logger.info("Device registration attempt \(attempt) of \(maxRegistrationRetries)")

                // Initialize API client and auth service if needed
                if serviceContainer.authenticationService == nil {
                    try await serviceContainer.initializeNetworkServices(with: params)
                }

                guard let authService = serviceContainer.authenticationService else {
                    throw SDKError.invalidState("Authentication service not available")
                }

                // Register device with backend
                let deviceRegistration = try await authService.registerDevice()

                // Store device ID locally
                try storeDeviceId(deviceRegistration.deviceId)
                await registrationState.setCachedDeviceId(deviceRegistration.deviceId)

                logger.info("Device registered successfully: \(deviceRegistration.deviceId.prefix(8))...")
                logger.debug("Device registration completed")
                await registrationState.clearRegistering()
                return // Success!

            } catch {
                lastError = error
                logger.error("Device registration attempt \(attempt) failed: \(error.localizedDescription)")

                // Check if error is retryable
                if !isRetryableError(error) {
                    logger.error("Non-retryable error, stopping registration attempts")
                    await registrationState.clearRegistering()
                    throw error
                }

                // Wait before retrying (except on last attempt)
                if attempt < maxRegistrationRetries {
                    logger.info("Waiting \(retryDelayNanoseconds / 1_000_000_000) seconds before retry...")
                    try? await Task.sleep(nanoseconds: retryDelayNanoseconds)
                }
            }
        }

        // All retries exhausted
        let finalError = lastError ?? SDKError.networkError("Device registration failed after \(maxRegistrationRetries) attempts")
        logger.error("Device registration failed after all retries: \(finalError.localizedDescription)")
        await registrationState.clearRegistering()
        throw finalError
    }

    /// Determine if an error is retryable
    /// - Parameter error: The error to check
    /// - Returns: true if the error is retryable (network issues, timeouts, etc.)
    private static func isRetryableError(_ error: Error) -> Bool {
        // Check for common retryable errors
        if let sdkError = error as? SDKError {
            switch sdkError {
            case .networkError, .timeout, .serverError:
                return true
            case .invalidAPIKey, .notInitialized, .invalidState, .validationFailed, .storageError:
                return false
            default:
                return false
            }
        }

        // Check for NSError codes
        if let nsError = error as NSError? {
            // Common network error codes that are retryable
            let retryableCodes = [
                NSURLErrorTimedOut,
                NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorNotConnectedToInternet,
                NSURLErrorDNSLookupFailed
            ]
            return retryableCodes.contains(nsError.code)
        }

        return false
    }

    // MARK: - Development Device Registration

    private static let devDeviceRegisteredKey = "com.runanywhere.sdk.devDeviceRegistered"

    /// Check if device is already registered in development mode
    private static func isDevDeviceRegistered() -> Bool {
        // Check Keychain first
        if let registered = try? KeychainManager.shared.retrieve(for: devDeviceRegisteredKey),
           registered == "true" {
            return true
        }

        // Fallback to UserDefaults for development
        return UserDefaults.standard.bool(forKey: devDeviceRegisteredKey)
    }

    /// Mark device as registered in development mode
    private static func markDevDeviceAsRegistered() {
        // Store in both Keychain and UserDefaults
        try? KeychainManager.shared.store("true", for: devDeviceRegisteredKey)
        UserDefaults.standard.set(true, forKey: devDeviceRegisteredKey)
    }

    /// Register device for development mode (non-blocking, silent failures)
    private static func registerDevDeviceIfNeeded() async {
        let logger = SDKLogger(category: "RunAnywhere.DevRegistration")

        // Check opt-out environment variable
        if ProcessInfo.processInfo.environment["RUNANYWHERE_DISABLE_DEV_REGISTRATION"] == "1" {
            logger.info("Dev device registration disabled via environment variable")
            return
        }

        // Check if already registered
        if isDevDeviceRegistered() {
            logger.info("✅ Device already registered in development mode (skipping)")
            return
        }

        logger.info("📝 Registering device in development mode...")

        do {
            try await registerDevDevice()
            markDevDeviceAsRegistered()
            logger.info("✅ Dev device registration successful")
        } catch {
            // Silent failure - don't block SDK initialization
            logger.warning("Dev device registration failed (non-critical): \(error.localizedDescription)")
        }
    }

    /// Perform the actual dev device registration
    private static func registerDevDevice() async throws {
        guard let params = initParams else {
            throw SDKError.notInitialized
        }

        // Collect device info using DeviceKitAdapter
        let deviceAdapter = DeviceKitAdapter()
        let deviceInfoResult = deviceAdapter.getDeviceInfo()
        let processorInfo = deviceAdapter.getProcessorInfo()
        let capabilities = deviceAdapter.getDeviceCapabilities()

        // Get or generate device ID (but DON'T store it yet - only after successful registration)
        let deviceId = getStoredDeviceId() ?? generateDeviceIdentifier()
        let isNewDevice = getStoredDeviceId() == nil

        // Create registration request with current timestamp for UPSERT
        let now = ISO8601DateFormatter().string(from: Date())
        let request = DevDeviceRegistrationRequest(
            deviceId: deviceId,
            deviceModel: deviceInfoResult.model,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            chipName: processorInfo.chipName,
            totalMemory: Int64(ProcessInfo.processInfo.physicalMemory),
            hasNeuralEngine: capabilities.hasNeuralEngine,
            architecture: processorInfo.architecture,
            formFactor: deviceInfoResult.name,
            sdkVersion: SDKConstants.version,
            platform: SDKConstants.platform,
            buildToken: BuildToken.token,
            lastSeenAt: now  // Will be updated on every registration via UPSERT
        )

        // Choose registration method based on configuration
        // IMPORTANT: Only proceed with storage if registration succeeds (throws on failure)
        if let supabaseConfig = params.supabaseConfig {
            // Use Supabase REST API (automatic in development mode)
            try await registerDevDeviceViaSupabase(request: request, config: supabaseConfig)
        } else {
            // Use traditional backend (production/staging)
            try await registerDevDeviceViaBackend(request: request, baseURL: params.baseURL)
        }

        // ✅ Registration succeeded! Now store device ID if it was newly generated
        if isNewDevice {
            try storeDeviceId(deviceId)
        }
    }

    /// Register device via traditional backend
    private static func registerDevDeviceViaBackend(request: DevDeviceRegistrationRequest, baseURL: URL) async throws {
        let url = baseURL.appendingPathComponent(APIEndpoint.devDeviceRegistration.path)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        // Perform request
        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SDKError.networkError("Invalid response from server")
        }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw SDKError.networkError("Registration failed with status code: \(httpResponse.statusCode)")
        }

        // Parse response (optional, for validation)
        let decoder = JSONDecoder()
        let _ = try decoder.decode(DevDeviceRegistrationResponse.self, from: data)
    }

    /// Register device via Supabase REST API
    private static func registerDevDeviceViaSupabase(request: DevDeviceRegistrationRequest, config: SupabaseConfig) async throws {
        let logger = SDKLogger(category: "RunAnywhere.DevRegistration")

        // Supabase REST API endpoint: POST /rest/v1/sdk_devices
        let url = config.projectURL
            .appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent("sdk_devices")

        logger.debug("Sending device registration)")
        logger.debug("Device ID: \(request.deviceId)")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        // Use UPSERT: resolution=merge-duplicates updates existing record based on unique constraint
        urlRequest.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(request)

        // Perform request
        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("❌ Invalid response from Supabase")
            throw SDKError.networkError("Invalid response from Supabase")
        }

        logger.debug("Supabase response: HTTP \(httpResponse.statusCode)")

        // Supabase returns 201 for successful inserts
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            // Try to extract error message from Supabase response
            var errorMessage = "Registration failed with status code: \(httpResponse.statusCode)"
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorData["message"] as? String {
                errorMessage = message
                logger.error("❌ Supabase error: \(message)")
            }

            // Also log the raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                logger.debug("Response body: \(responseString)")
            }

            throw SDKError.networkError(errorMessage)
        }

        logger.info("✅ Device successfully registered with Supabase!")
    }

    // MARK: - Analytics Submission

    /// Submit generation analytics via Supabase (development mode)
    private static func submitAnalyticsViaSupabase(
        request: DevAnalyticsSubmissionRequest,
        config: SupabaseConfig
    ) async throws {
        let logger = SDKLogger(category: "RunAnywhere.Analytics")

        let url = config.projectURL
            .appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent("sdk_generation_analytics")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SDKError.networkError("Invalid response from Supabase")
        }

        logger.debug("Analytics HTTP Response: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            var errorMessage = "Analytics submission failed: \(httpResponse.statusCode)"
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                logger.debug("error response: \(errorData)")
                if let message = errorData["message"] as? String {
                    errorMessage = message
                }
            }
            throw SDKError.networkError(errorMessage)
        }

        logger.debug("Analytics submission successful")
    }

    /// Submit generation analytics via backend (production mode - future)
    private static func submitAnalyticsViaBackend(
        request: DevAnalyticsSubmissionRequest,
        baseURL: URL
    ) async throws {
        let url = baseURL.appendingPathComponent(APIEndpoint.devAnalytics.path)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        let (_, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw SDKError.networkError("Analytics submission failed")
        }
    }

    /// Submit generation analytics (public API)
    /// - Note: Only submits in development mode; fails silently on errors
    public static func submitGenerationAnalytics(
        generationId: String,
        modelId: String,
        performanceMetrics: PerformanceMetrics,
        inputTokens: Int,
        outputTokens: Int,
        success: Bool,
        executionTarget: String
    ) async {
        guard let params = initParams else { return }
        guard params.environment == .development else { return }

        // Non-blocking background submission
        Task.detached(priority: .background) {
            do {
                let deviceId = getStoredDeviceId() ?? "unknown"

                // Capture host app information
                let hostAppIdentifier = Bundle.main.bundleIdentifier
                let hostAppName = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
                    ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
                let hostAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

                let request = DevAnalyticsSubmissionRequest(
                    generationId: generationId,
                    deviceId: deviceId,
                    modelId: modelId,
                    timeToFirstTokenMs: performanceMetrics.timeToFirstTokenMs,
                    tokensPerSecond: performanceMetrics.tokensPerSecond,
                    totalGenerationTimeMs: performanceMetrics.inferenceTimeMs,
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    success: success,
                    executionTarget: executionTarget,
                    buildToken: BuildToken.token,
                    sdkVersion: SDKConstants.version,
                    timestamp: ISO8601DateFormatter().string(from: Date()),
                    hostAppIdentifier: hostAppIdentifier,
                    hostAppName: hostAppName,
                    hostAppVersion: hostAppVersion
                )


                if let supabaseConfig = params.supabaseConfig {
                    try await submitAnalyticsViaSupabase(request: request, config: supabaseConfig)
                } else {
                    try await submitAnalyticsViaBackend(request: request, baseURL: params.baseURL)
                }
            } catch {
                // Fail silently - analytics should never break the SDK
                SDKLogger(category: "RunAnywhere.Analytics").debug("Analytics submission failed (non-critical): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Device ID Management

    private static let deviceIdKey = "com.runanywhere.sdk.deviceId"

    /// Get stored device ID from local persistence
    private static func getStoredDeviceId() -> String? {
        let logger = SDKLogger(category: "RunAnywhere.DeviceID")

        // Try keychain first (survives app reinstalls)
        if let keychainId = KeychainManager.shared.retrieveDeviceUUID() {
            logger.info("📱 Retrieved device ID from Keychain: \(keychainId)")
            return keychainId
        }

        // Fallback to UserDefaults (does NOT survive app uninstall)
        if let userDefaultsId = UserDefaults.standard.string(forKey: deviceIdKey) {
            logger.debug("Retrieved device ID from UserDefaults: \(userDefaultsId)")
            return userDefaultsId
        }

        logger.debug("No stored device ID found")
        return nil
    }

    /// Store device ID in local persistence
    private static func storeDeviceId(_ deviceId: String) throws {
        guard !deviceId.isEmpty else {
            throw SDKError.validationFailed("Device ID cannot be empty")
        }

        let logger = SDKLogger(category: "RunAnywhere.DeviceID")

        // ALWAYS store in keychain (persists across app reinstalls)
        try KeychainManager.shared.storeDeviceUUID(deviceId)
        logger.debug("Stored device ID in Keychain: \(deviceId)")

        // Also store in UserDefaults as fallback for quick access
        UserDefaults.standard.set(deviceId, forKey: deviceIdKey)
        UserDefaults.standard.synchronize()
        logger.debug("Stored device ID in UserDefaults: \(deviceId)")
    }

    /// Clear stored device ID
    private static func clearStoredDeviceId() {
        // Clear from keychain using the deviceUUID key
        try? KeychainManager.shared.delete(for: "com.runanywhere.sdk.device.uuid")

        // Clear from UserDefaults
        UserDefaults.standard.removeObject(forKey: deviceIdKey)
        UserDefaults.standard.synchronize()

        // Clear cache
        Task {
            await registrationState.setCachedDeviceId(nil)
        }
    }

    /// Generate a unique device identifier
    private static func generateDeviceIdentifier() -> String {
        let logger = SDKLogger(category: "RunAnywhere.DeviceID")

        #if os(iOS) || os(tvOS) || os(watchOS)
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString {
            logger.debug("Generated device ID from identifierForVendor: \(vendorId)")
            return vendorId
        }
        #endif

        // Fallback to random UUID
        let randomId = UUID().uuidString
        logger.debug("Using random UUID (identifierForVendor unavailable): \(randomId)")
        return randomId
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
        options: RunAnywhereGenerationOptions? = nil
    ) async throws -> GenerationResult {
        EventBus.shared.publish(SDKGenerationEvent.started(prompt: prompt))

        do {
            // Ensure initialized
            guard isInitialized else {
                throw SDKError.notInitialized
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
        options: RunAnywhereGenerationOptions? = nil
    ) async throws -> StreamingResult {
        EventBus.shared.publish(SDKGenerationEvent.started(prompt: prompt))

        // Ensure initialized
        guard isInitialized else {
            throw SDKError.notInitialized
        }

        // Lazy device registration on first API call
        try await ensureDeviceRegistered()

        return serviceContainer.streamingService.generateStreamWithMetrics(
            prompt: prompt,
            options: options ?? RunAnywhereGenerationOptions()
        )
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
                throw SDKError.notInitialized
            }

            // Lazy device registration on first API call
            try await ensureDeviceRegistered()

            // Get model info for lifecycle tracking
            let modelInfo = serviceContainer.modelRegistry.getModel(by: modelId)
            let framework = modelInfo?.preferredFramework ?? .llamaCpp
            let modelName = modelInfo?.name ?? modelId

            // Notify lifecycle manager
            await MainActor.run {
                ModelLifecycleTracker.shared.modelWillLoad(
                    modelId: modelId,
                    modelName: modelName,
                    framework: framework,
                    modality: .llm
                )
            }

            let loadedModel = try await serviceContainer.modelLoadingService.loadModel(modelId)

            // IMPORTANT: Set the loaded model in the generation service
            serviceContainer.generationService.setCurrentModel(loadedModel)

            // Notify lifecycle manager of successful load
            await MainActor.run {
                ModelLifecycleTracker.shared.modelDidLoad(
                    modelId: modelId,
                    modelName: modelName,
                    framework: framework,
                    modality: .llm,
                    memoryUsage: modelInfo?.memoryRequired
                )
            }

            EventBus.shared.publish(SDKModelEvent.loadCompleted(modelId: modelId))
        } catch {
            // Notify lifecycle manager of failure
            await MainActor.run {
                ModelLifecycleTracker.shared.modelLoadFailed(
                    modelId: modelId,
                    modality: .llm,
                    error: error.localizedDescription
                )
            }
            EventBus.shared.publish(SDKModelEvent.loadFailed(modelId: modelId, error: error))
            throw error
        }
    }

    /// Load an STT (Speech-to-Text) model by ID
    /// This initializes the STT component and loads the model into memory
    /// - Parameter modelId: The model identifier
    public static func loadSTTModel(_ modelId: String) async throws {
        EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: modelId))

        do {
            // Ensure initialized
            guard isInitialized else {
                throw SDKError.notInitialized
            }

            // Get model info for lifecycle tracking
            let modelInfo = serviceContainer.modelRegistry.getModel(by: modelId)
            let framework = modelInfo?.preferredFramework ?? .whisperKit
            let modelName = modelInfo?.name ?? modelId

            // Notify lifecycle manager
            await MainActor.run {
                ModelLifecycleTracker.shared.modelWillLoad(
                    modelId: modelId,
                    modelName: modelName,
                    framework: framework,
                    modality: .stt
                )
            }

            // Create STT configuration
            let sttConfig = STTConfiguration(modelId: modelId)

            // Create and initialize STT component on MainActor
            let sttComponent = await MainActor.run {
                STTComponent(configuration: sttConfig)
            }
            try await sttComponent.initialize()

            // Store the component for later use
            await MainActor.run {
                _loadedSTTComponent = sttComponent
            }

            // Notify lifecycle manager of successful load
            await MainActor.run {
                ModelLifecycleTracker.shared.modelDidLoad(
                    modelId: modelId,
                    modelName: modelName,
                    framework: framework,
                    modality: .stt,
                    memoryUsage: modelInfo?.memoryRequired
                )
            }

            EventBus.shared.publish(SDKModelEvent.loadCompleted(modelId: modelId))
        } catch {
            // Notify lifecycle manager of failure
            await MainActor.run {
                ModelLifecycleTracker.shared.modelLoadFailed(
                    modelId: modelId,
                    modality: .stt,
                    error: error.localizedDescription
                )
            }
            EventBus.shared.publish(SDKModelEvent.loadFailed(modelId: modelId, error: error))
            throw error
        }
    }

    /// Load a TTS (Text-to-Speech) model by ID
    /// This initializes the TTS component and loads the model into memory
    /// - Parameter modelId: The model identifier (voice name)
    public static func loadTTSModel(_ modelId: String) async throws {
        EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: modelId))

        do {
            // Ensure initialized
            guard isInitialized else {
                throw SDKError.notInitialized
            }

            // Get model info for lifecycle tracking
            let modelInfo = serviceContainer.modelRegistry.getModel(by: modelId)
            let framework = modelInfo?.preferredFramework ?? .onnx
            let modelName = modelInfo?.name ?? modelId

            // Notify lifecycle manager
            await MainActor.run {
                ModelLifecycleTracker.shared.modelWillLoad(
                    modelId: modelId,
                    modelName: modelName,
                    framework: framework,
                    modality: .tts
                )
            }

            // Create TTS configuration
            let ttsConfig = TTSConfiguration(voice: modelId)

            // Create and initialize TTS component on MainActor
            let ttsComponent = await MainActor.run {
                TTSComponent(configuration: ttsConfig)
            }
            try await ttsComponent.initialize()

            // Store the component for later use
            await MainActor.run {
                _loadedTTSComponent = ttsComponent
            }

            // Notify lifecycle manager of successful load
            await MainActor.run {
                ModelLifecycleTracker.shared.modelDidLoad(
                    modelId: modelId,
                    modelName: modelName,
                    framework: framework,
                    modality: .tts,
                    memoryUsage: modelInfo?.memoryRequired
                )
            }

            EventBus.shared.publish(SDKModelEvent.loadCompleted(modelId: modelId))
        } catch {
            // Notify lifecycle manager of failure
            await MainActor.run {
                ModelLifecycleTracker.shared.modelLoadFailed(
                    modelId: modelId,
                    modality: .tts,
                    error: error.localizedDescription
                )
            }
            EventBus.shared.publish(SDKModelEvent.loadFailed(modelId: modelId, error: error))
            throw error
        }
    }

    // MARK: - Loaded Component Storage

    @MainActor
    private static var _loadedSTTComponent: STTComponent?

    @MainActor
    private static var _loadedTTSComponent: TTSComponent?

    /// Get the currently loaded STT component
    @MainActor
    public static var loadedSTTComponent: STTComponent? {
        return _loadedSTTComponent
    }

    /// Get the currently loaded TTS component
    @MainActor
    public static var loadedTTSComponent: TTSComponent? {
        return _loadedTTSComponent
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

    // MARK: - Multi-Adapter Support (NEW)

    /// Register a framework adapter with optional priority
    /// Higher priority adapters are preferred when multiple can handle the same model
    /// - Parameters:
    ///   - adapter: The framework adapter to register
    ///   - priority: Priority level (higher = preferred, default: 100)
    public static func registerFrameworkAdapter(_ adapter: UnifiedFrameworkAdapter, priority: Int = 100) {
        // Note: Adapter registration can happen before SDK initialization
        // This allows registering adapters during app setup
        serviceContainer.adapterRegistry.register(adapter, priority: priority)
    }

    /// Get all adapters capable of handling a specific model
    /// - Parameter modelId: The model identifier
    /// - Returns: Array of framework types that can handle this model
    public static func availableAdapters(for modelId: String) async -> [LLMFramework] {
        guard isInitialized else {
            return []
        }

        // Get model info
        guard let model = serviceContainer.modelRegistry.getModel(by: modelId) else {
            return []
        }

        // Determine modality
        let modality: FrameworkModality
        if model.category == .speechRecognition || model.preferredFramework == .whisperKit {
            modality = .voiceToText
        } else {
            modality = .textToText
        }

        // Get all capable adapters
        let adapters = await serviceContainer.adapterRegistry.findAllAdapters(for: model, modality: modality)
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
        let result = try await RunAnywhere.generate(contextPrompt)

        messages.append("Assistant: \(result.text)")
        return result.text
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
