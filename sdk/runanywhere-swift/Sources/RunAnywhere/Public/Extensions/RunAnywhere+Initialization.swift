import Foundation

// MARK: - SDK Initialization

extension RunAnywhere {

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
    internal static func initialize(with params: SDKInitParams) throws {
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
}
