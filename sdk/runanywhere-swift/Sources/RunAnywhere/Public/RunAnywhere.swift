//
//  RunAnywhere.swift
//  RunAnywhere SDK
//
//  The main entry point for the RunAnywhere SDK.
//  Contains SDK initialization, state management, and event access.
//

import Combine
import Foundation
#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#endif

/// The RunAnywhere SDK - Single entry point for on-device AI
public enum RunAnywhere {

    // MARK: - Internal State Management

    /// Internal configuration storage
    internal static var configurationData: ConfigurationData?
    internal static var initParams: SDKInitParams?
    internal static var currentEnvironment: SDKEnvironment?
    internal static var isInitialized = false

    /// Track if network bootstrap is complete (makes ensureDeviceRegistered O(1) after first call)
    internal static var isBootstrapped = false

    /// Access to service container (through the shared instance for now)
    internal static var serviceContainer: ServiceContainer {
        ServiceContainer.shared
    }

    // MARK: - SDK State

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
     * Initialize the RunAnywhere SDK for staging or production
     *
     * This method performs simple, fast initialization with no network calls:
     *
     * 1. **Validation**: Validate API key, URL, and environment compatibility
     * 2. **Logging**: Initialize logging system based on environment
     * 3. **Storage**: Store parameters locally (no keychain for dev mode)
     * 4. **State**: Mark SDK as initialized
     *
     * NO network calls, NO device registration, NO complex bootstrapping.
     * Device registration happens lazily on first API call.
     *
     * - Parameters:
     *   - apiKey: Your RunAnywhere API key from the console (required for staging/production)
     *   - baseURL: Backend API base URL (must be valid HTTPS for production)
     *   - environment: SDK environment (development/staging/production)
     *
     * - Throws: RunAnywhereError if validation fails
     * - Note: Production environment cannot be used in DEBUG builds
     */
    public static func initialize(
        apiKey: String,
        baseURL: URL,
        environment: SDKEnvironment = .production
    ) throws {
        let params = try SDKInitParams(apiKey: apiKey, baseURL: baseURL, environment: environment)
        try initialize(with: params)
    }

    /// Initialize the SDK with string URL for staging or production
    /// - Parameters:
    ///   - apiKey: Your RunAnywhere API key (required for staging/production)
    ///   - baseURL: Base URL string for API requests (must be valid HTTPS for production)
    ///   - environment: Environment mode (default: production)
    /// - Throws: RunAnywhereError if URL is invalid or validation fails
    /// - Note: Production environment cannot be used in DEBUG builds
    public static func initialize(
        apiKey: String,
        baseURL: String,
        environment: SDKEnvironment = .production
    ) throws {
        let params = try SDKInitParams(apiKey: apiKey, baseURL: baseURL, environment: environment)
        try initialize(with: params)
    }

    /// Initialize the SDK for development mode
    ///
    /// Development mode:
    /// - Does not require an API key or backend URL
    /// - Logs are stored locally (verbose debug level)
    /// - Uses Supabase for dev analytics (no backend required)
    /// - Network calls are minimized
    ///
    /// - Parameter apiKey: Optional API key (not required for development)
    public static func initializeForDevelopment(apiKey: String = "") throws {
        let params = SDKInitParams(forDevelopmentWithAPIKey: apiKey)
        try initialize(with: params)
    }

    /// Initialize the SDK with parameters
    /// - Parameter params: SDK initialization parameters
    /// - Note: Validation is performed in SDKInitParams.init(), so params are already validated here
    internal static func initialize(with params: SDKInitParams) throws {
        // Return early if already initialized
        guard !isInitialized else {
            return
        }

        let initStartTime = CFAbsoluteTimeGetCurrent()
        let logger = SDKLogger(category: "RunAnywhere.Init")

        // Dispatch SDK init started event
        EventPublisher.shared.track(SDKLifecycleEvent.initStarted)

        do {
            // Note: API key, URL, and environment validation is already done in SDKInitParams.init()

            // Step 1: Initialize logging system based on environment
            RunAnywhere.setLogLevel(params.environment.defaultLogLevel)

            // Step 2: Store parameters locally
            initParams = params
            currentEnvironment = params.environment

            // Only store in keychain for non-development environments
            if params.environment != .development {
                try KeychainManager.shared.storeSDKParams(params)
            }

            // Database initialization deferred until stable implementation is ready
            // See: Infrastructure/Persistence/DatabaseManager.swift

            // Step 4: Services are lazily initialized when first accessed
            // No additional setup needed here

            // Mark as initialized
            isInitialized = true

            // Calculate init duration
            let initDurationMs = (CFAbsoluteTimeGetCurrent() - initStartTime) * 1000

            logger.info("✅ SDK initialization completed in \(String(format: "%.1f", initDurationMs))ms (\(params.environment.description) mode)")

            // Dispatch SDK init completed event with actual duration
            EventPublisher.shared.track(SDKLifecycleEvent.initCompleted(durationMs: initDurationMs))

            // Step 5: Device registration in background (non-blocking)
            // Happens for all environments - ensures device is registered on launch
            logger.debug("Triggering device registration in background...")
            Task.detached(priority: .userInitiated) {
                do {
                    try await ensureDeviceRegistered()
                    SDKLogger(category: "RunAnywhere.Init").info("✅ Device registered successfully")
                } catch {
                    SDKLogger(category: "RunAnywhere.Init")
                        .warning("⚠️ Device registration failed (non-critical): \(error.localizedDescription)")
                    // Don't fail SDK initialization if device registration fails
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
