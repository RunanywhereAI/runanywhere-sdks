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

// MARK: - SDK Initialization Flow
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │                         SDK INITIALIZATION FLOW                              │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// PHASE 1: Core Init (Synchronous, ~1-5ms, No Network)
// ─────────────────────────────────────────────────────
//   initialize() or initializeForDevelopment()
//     ├─ Validate params (API key, URL, environment)
//     ├─ Set log level
//     ├─ Store params locally
//     ├─ Store in Keychain (production/staging only)
//     └─ Mark: isInitialized = true
//
// PHASE 2: Services Init (Async, ~100-500ms, Network Required)
// ────────────────────────────────────────────────────────────
//   completeServicesInitialization()
//     ├─ Setup API Client
//     │    ├─ Development: Use Supabase
//     │    └─ Production/Staging: Authenticate with backend
//     ├─ Create Core Services
//     │    ├─ ModelInfoService
//     │    └─ ModelAssignmentService
//     ├─ Load Models (from remote API)
//     ├─ Initialize EventPublisher (telemetry → backend)
//     └─ Register Device with Backend
//
// USAGE:
// ──────
//   // Development mode (default)
//   try RunAnywhere.initialize()
//
//   // Production mode - requires API key and backend URL
//   try RunAnywhere.initialize(
//       apiKey: "your_api_key",
//       baseURL: "https://api.runanywhere.ai",
//       environment: .production
//   )
//

/// The RunAnywhere SDK - Single entry point for on-device AI
public enum RunAnywhere {

    // MARK: - Internal State Management

    /// Internal init params storage
    internal static var initParams: SDKInitParams?
    internal static var currentEnvironment: SDKEnvironment?
    internal static var isInitialized = false

    /// Track if services initialization is complete (makes API calls O(1) after first use)
    internal static var hasCompletedServicesInit = false

    /// Access to service container
    internal static var serviceContainer: ServiceContainer {
        ServiceContainer.shared
    }

    // MARK: - SDK State

    /// Check if SDK is initialized (Phase 1 complete)
    public static var isSDKInitialized: Bool {
        isInitialized
    }

    /// Check if services are fully ready (Phase 2 complete)
    public static var areServicesReady: Bool {
        hasCompletedServicesInit
    }

    /// Check if SDK is active and ready for use
    public static var isActive: Bool {
        isInitialized && initParams != nil
    }

    /// Current SDK version
    public static var version: String {
        SDKConstants.version
    }

    /// Current environment (nil if not initialized)
    public static var environment: SDKEnvironment? {
        currentEnvironment
    }

    /// Device ID (Keychain-persisted, survives reinstalls)
    public static var deviceId: String {
        DeviceIdentity.persistentUUID
    }

    // MARK: - Event Access

    /// Access to all SDK events for subscription-based patterns
    public static var events: EventBus {
        EventBus.shared
    }

    // MARK: - Authentication Info (Production/Staging only)

    /// Get current user ID from authentication
    /// - Returns: User ID if authenticated, nil otherwise
    public static func getUserId() -> String? {
        CppBridge.State.userId
    }

    /// Get current organization ID from authentication
    /// - Returns: Organization ID if authenticated, nil otherwise
    public static func getOrganizationId() -> String? {
        CppBridge.State.organizationId
    }

    /// Check if currently authenticated
    /// - Returns: true if authenticated with valid token
    public static var isAuthenticated: Bool {
        CppBridge.State.isAuthenticated
    }

    /// Check if device is registered with backend
    public static func isDeviceRegistered() async -> Bool {
        // First try C++ state
        if CppBridge.State.isDeviceRegistered {
            return true
        }
        // Fallback to Swift service
        return await serviceContainer.deviceRegistrationService.isRegistered
    }

    // MARK: - SDK Reset (Testing)

    /// Reset SDK state (for testing purposes)
    /// Clears all initialization state and cached data
    public static func reset() {
        let logger = SDKLogger(category: "RunAnywhere.Reset")
        logger.info("Resetting SDK state...")

        isInitialized = false
        hasCompletedServicesInit = false
        initParams = nil
        currentEnvironment = nil

        // Shutdown all C++ bridges and state
        CppBridge.shutdown()
        CppBridge.State.shutdown()

        serviceContainer.reset()

        logger.info("SDK state reset completed")
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - SDK Initialization
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * Initialize the RunAnywhere SDK
     *
     * This performs fast synchronous initialization, then starts async services in background.
     * The SDK is usable immediately - services will be ready when first API call is made.
     *
     * **Phase 1 (Sync, ~1-5ms):** Validates params, sets up logging, stores config
     * **Phase 2 (Background):** Network auth, service creation, model loading, device registration
     *
     * ## Usage Examples
     *
     * ```swift
     * // Development mode (default)
     * try RunAnywhere.initialize()
     *
     * // Production mode - requires API key and backend URL
     * try RunAnywhere.initialize(
     *     apiKey: "your_api_key",
     *     baseURL: "https://api.runanywhere.ai",
     *     environment: .production
     * )
     * ```
     *
     * - Parameters:
     *   - apiKey: API key (optional for development, required for production/staging)
     *   - baseURL: Backend API base URL (optional for development, required for production/staging)
     *   - environment: SDK environment (default: .development)
     *
     * - Throws: SDKError if validation fails
     */
    public static func initialize(
        apiKey: String? = nil,
        baseURL: String? = nil,
        environment: SDKEnvironment = .development
    ) throws {
        let params: SDKInitParams

        if environment == .development {
            // Development mode - use Supabase, no auth needed
            params = SDKInitParams(forDevelopmentWithAPIKey: apiKey ?? "")
        } else {
            // Production/Staging mode - require API key and URL
            guard let apiKey = apiKey, !apiKey.isEmpty else {
                throw SDKError.general(.invalidConfiguration, "API key is required for \(environment.description) mode")
            }
            guard let baseURL = baseURL, !baseURL.isEmpty else {
                throw SDKError.general(.invalidConfiguration, "Base URL is required for \(environment.description) mode")
            }
            params = try SDKInitParams(apiKey: apiKey, baseURL: baseURL, environment: environment)
        }

        try performCoreInit(with: params, startBackgroundServices: true)
    }

    /// Initialize with URL type for base URL
    public static func initialize(
        apiKey: String,
        baseURL: URL,
        environment: SDKEnvironment = .production
    ) throws {
        let params = try SDKInitParams(apiKey: apiKey, baseURL: baseURL, environment: environment)
        try performCoreInit(with: params, startBackgroundServices: true)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Phase 1: Core Initialization (Synchronous)
    // ═══════════════════════════════════════════════════════════════════════════

    /// Perform core initialization (Phase 1)
    /// - Parameters:
    ///   - params: SDK initialization parameters
    ///   - startBackgroundServices: If true, starts Phase 2 in background task
    private static func performCoreInit(with params: SDKInitParams, startBackgroundServices: Bool) throws {
        // Return early if already initialized
        guard !isInitialized else { return }

        let initStartTime = CFAbsoluteTimeGetCurrent()

        // Step 1: Set environment FIRST so Logging.shared initializes with correct config
        // This must happen before any SDKLogger usage to ensure logs appear correctly
        currentEnvironment = params.environment
        initParams = params

        // Step 2: Apply environment-specific logging configuration
        Logging.shared.applyEnvironmentConfiguration(params.environment)

        // Step 3: Register platform adapter for C++ → Swift log bridge
        // This must happen early so all C++ logs (from runanywhere-core) route to SDKLogger
        SwiftPlatformAdapter.shared.register()

        // Now safe to create logger and track events
        // Note: C++ event bridge is registered by CppBridge.initialize() in Step 3
        let logger = SDKLogger(category: "RunAnywhere.Init")
        EventPublisher.shared.track(SDKLifecycleEvent.initStarted)

        do {

            // Step 4: Persist to Keychain (production/staging only)
            if params.environment != .development {
                try KeychainManager.shared.storeSDKParams(params)
            }

            // Mark Phase 1 complete
            isInitialized = true

            let initDurationMs = (CFAbsoluteTimeGetCurrent() - initStartTime) * 1000
            logger.info("✅ Phase 1 complete in \(String(format: "%.1f", initDurationMs))ms (\(params.environment.description))")

            EventPublisher.shared.track(SDKLifecycleEvent.initCompleted(durationMs: initDurationMs))

            // Optionally start Phase 2 in background
            if startBackgroundServices {
                logger.debug("Starting Phase 2 (services) in background...")
                Task.detached(priority: .userInitiated) {
                    do {
                        try await completeServicesInitialization()
                        SDKLogger(category: "RunAnywhere.Init").info("✅ Phase 2 complete (background)")
                    } catch {
                        SDKLogger(category: "RunAnywhere.Init")
                            .warning("⚠️ Phase 2 failed (non-critical): \(error.localizedDescription)")
                    }
                }
            }

        } catch {
            logger.error("❌ Initialization failed: \(error.localizedDescription)")
            initParams = nil
            isInitialized = false
            EventPublisher.shared.track(SDKLifecycleEvent.initFailed(error: SDKError.from(error)))
            throw error
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Phase 2: Services Initialization (Async)
    // ═══════════════════════════════════════════════════════════════════════════

    /// Complete services initialization (Phase 2)
    ///
    /// Called automatically in background by `initialize()`, or can be awaited directly
    /// via `initializeAsync()`. Safe to call multiple times - returns immediately if already done.
    ///
    /// This method:
    /// 1. Sets up API client (with authentication for production/staging)
    /// 2. Initializes C++ model registry and bridges
    /// 3. Initializes EventPublisher for telemetry
    /// 4. Registers device with backend
    public static func completeServicesInitialization() async throws {
        // Fast path: already completed
        if hasCompletedServicesInit {
            return
        }

        guard let params = initParams, let environment = currentEnvironment else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        let logger = SDKLogger(category: "RunAnywhere.Services")

        // Register platform backend (Foundation Models + System TTS)
        // This registers Swift callbacks with C++, then C++ registers
        // the module and service providers with the service registry.
        // Must be called on MainActor and before services use the registry.
        await MainActor.run {
            CppBridge.Platform.register()
        }

        // Check if services need initialization
        let httpNeedsInit = await !CppBridge.HTTP.shared.isConfigured

        if httpNeedsInit {
            logger.info("Initializing services for \(environment.description) mode...")

            // Step 1: Configure HTTP transport (unified in CppBridge)
            try await setupHTTP(params: params, environment: environment, logger: logger)

            // Step 2: Create model assignment service (uses CppBridge.ModelRegistry directly)
            await setupModelServices(logger: logger)
        }

        // Step 3: Initialize C++ state and bridges
        CppBridge.State.initialize(
            environment: environment,
            apiKey: params.apiKey,
            baseURL: params.baseURL,
            deviceId: DeviceIdentity.persistentUUID
        )

        // Initialize telemetry and events bridges
        CppBridge.initialize(environment: environment)

        // Initialize EventPublisher for Swift-originated events
        EventPublisher.shared.initialize(environment: environment)
        logger.debug("C++ state and bridges initialized")

        // Step 4: Set base directory for C++ model paths
        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try CppBridge.ModelPaths.setBaseDirectory(documentsURL)
            logger.debug("Model paths base directory set")
        }

        // Step 5: Register device via CppBridge
        await serviceContainer.deviceRegistrationService.registerIfNeeded(
            networkService: CppBridge.HTTP.shared,
            environment: environment
        )

        // Step 6: Discover already-downloaded models on file system
        // This scans the models directory and updates the registry for models found on disk
        let discoveryResult = await CppBridge.ModelRegistry.shared.discoverDownloadedModels()
        if discoveryResult.discoveredCount > 0 {
            logger.info("Discovered \(discoveryResult.discoveredCount) downloaded models on startup")
        }

        // Mark Phase 2 complete
        hasCompletedServicesInit = true
    }

    /// Ensure services are ready before API calls (internal guard)
    /// O(1) after first successful initialization
    internal static func ensureServicesReady() async throws {
        if hasCompletedServicesInit {
            return // O(1) fast path
        }
        try await completeServicesInitialization()
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Private: Service Setup Helpers
    // ═══════════════════════════════════════════════════════════════════════════

    /// Setup HTTP transport via CppBridge.HTTP
    private static func setupHTTP(
        params: SDKInitParams,
        environment: SDKEnvironment,
        logger: SDKLogger
    ) async throws {
        switch environment {
        case .development:
            // Use C++ development config for Supabase (cross-platform)
            if await CppBridge.DevConfig.configureHTTP() {
                logger.debug("HTTP: Supabase from C++ config (development)")
            } else {
                await CppBridge.HTTP.shared.configure(baseURL: params.baseURL, apiKey: params.apiKey)
                logger.debug("HTTP: Provided URL (development)")
            }

        case .staging, .production:
            // Configure HTTP first
            await CppBridge.HTTP.shared.configure(baseURL: params.baseURL, apiKey: params.apiKey)

            // Authenticate via CppBridge.Auth
            try await CppBridge.Auth.authenticate(apiKey: params.apiKey)
            logger.info("Authenticated for \(environment.description)")
        }
    }

    /// Setup model services
    /// Model registry is handled by CppBridge.ModelRegistry directly
    private static func setupModelServices(logger: SDKLogger) async {
        logger.debug("Setting up model services...")

        // ModelAssignmentService uses CppBridge.ModelRegistry directly
        let modelAssignmentService = ModelAssignmentService(
            networkService: CppBridge.HTTP.shared
        )
        serviceContainer.setModelAssignmentService(modelAssignmentService)

        logger.debug("Model services initialized")
    }
}
