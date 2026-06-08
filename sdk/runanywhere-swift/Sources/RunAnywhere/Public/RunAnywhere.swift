//
//  RunAnywhere.swift
//  RunAnywhere SDK
//
//  The main entry point for the RunAnywhere SDK.
//  Two-phase initialization is owned by commons (rac_sdk_init.h):
//    * Phase 1 → rac_sdk_init_phase1_proto (validate + state init)
//    * Phase 2 → rac_sdk_init_phase2_proto (auth/refresh, device
//      registration, model assignments, telemetry flush, model discovery)
//    * HTTP retry → rac_sdk_retry_http_proto
//  Swift retains only the parts that cannot move into C++:
//    * Task.detached spawning + _servicesInitLock concurrency primitive
//    * Keychain SDK params persistence (Apple-specific)
//    * MainActor platform-plugin/callback registration
//    * URLSession HTTP transport implementation and adapter configuration
//

import Foundation

/// The RunAnywhere SDK - Single entry point for on-device AI
public enum RunAnywhere {

    // MARK: - Internal State Management

    /// Internal init params storage
    internal static var initParams: SDKInitParams?
    internal static var currentEnvironment: SDKEnvironment?
    internal static var isInitializedFlag = false

    /// Track if services initialization is complete (makes API calls O(1) after first use)
    internal static var hasCompletedServicesInit = false
    /// Track if HTTP/auth setup succeeded (separate from core services so auth can be retried on reconnect)
    internal static var hasCompletedHTTPSetup = false
    /// Serialized Phase 2 task — ensures only one init runs at a time.
    /// Concurrent callers of completeServicesInitialization() await this shared task
    /// instead of racing through the init logic with an unprotected boolean guard.
    private static var _servicesInitTask: Task<Void, Error>?
    /// Serializes the check-and-set on `_servicesInitTask` so two concurrent callers
    /// can't both observe `nil` and spawn duplicate init tasks.
    private static let _servicesInitLock = DispatchQueue(label: "com.runanywhere.sdk.servicesInit")

    // MARK: - SDK State

    /// Check if SDK is initialized (Phase 1 complete).
    public static var isInitialized: Bool { isInitializedFlag }

    /// Check if services are fully ready (Phase 2 complete)
    public static var areServicesReady: Bool { hasCompletedServicesInit }

    /// Check if SDK is active and ready for use
    public static var isActive: Bool { isInitializedFlag && initParams != nil }

    /// Current SDK version
    public static var version: String { SDKConstants.version }

    /// Current environment (nil if not initialized)
    public static var environment: SDKEnvironment? { currentEnvironment }

    /// Device ID (Keychain-persisted, survives reinstalls)
    /// Resolved by commons via the device-identity chain
    /// (secure_get → vendor ID → freshly synthesized UUID).
    public static var deviceId: String { CppBridge.Device.persistentId }

    // MARK: - Event Access

    /// Access to all SDK events for subscription-based patterns
    public static var events: EventBus { EventBus.shared }

    // MARK: - Authentication Info (Production/Staging only)

    /// Get current user ID from authentication
    public static func getUserId() -> String? { CppBridge.State.userId }

    /// Get current organization ID from authentication
    public static func getOrganizationId() -> String? { CppBridge.State.organizationId }

    /// Check if currently authenticated
    public static var isAuthenticated: Bool { CppBridge.Auth.isAuthenticated }

    /// Check if device is registered with backend
    public static func isDeviceRegistered() -> Bool { CppBridge.Device.isRegistered }

    // MARK: - SDK Reset (Testing)

    /// Reset SDK state (for testing purposes)
    public static func reset() async {
        let logger = SDKLogger(category: "RunAnywhere.Reset")
        logger.info("Resetting SDK state...")

        isInitializedFlag = false
        hasCompletedServicesInit = false
        hasCompletedHTTPSetup = false
        initParams = nil
        currentEnvironment = nil

        await CppBridge.shutdown()
        CppBridge.State.shutdown()

        logger.info("SDK state reset completed")
    }

    // MARK: - SDK Initialization

    /// Initialize the RunAnywhere SDK.
    /// Phase 1 runs synchronously; Phase 2 spawns in a detached Task.
    public static func initialize(
        apiKey: String? = nil,
        baseURL: String? = nil,
        environment: SDKEnvironment = .development
    ) throws {
        let params: SDKInitParams
        if environment == .development {
            params = SDKInitParams(forDevelopmentWithAPIKey: apiKey ?? "")
        } else {
            params = try SDKInitParams(
                apiKey: apiKey ?? "",
                baseURL: baseURL ?? "",
                environment: environment
            )
        }
        try performCoreInit(with: params, startBackgroundServices: true)
    }

    /// Initialize with URL type for base URL.
    public static func initialize(
        apiKey: String,
        baseURL: URL,
        environment: SDKEnvironment = .production
    ) throws {
        let params = try SDKInitParams(apiKey: apiKey, baseURL: baseURL, environment: environment)
        try performCoreInit(with: params, startBackgroundServices: true)
    }

    // MARK: - Phase 1: Core Initialization (delegated to C++)

    private static func performCoreInit(with params: SDKInitParams, startBackgroundServices: Bool) throws {
        guard !isInitializedFlag else { return }

        let initStartTime = CFAbsoluteTimeGetCurrent()

        // Set environment first so logging boots with correct config.
        currentEnvironment = params.environment
        initParams = params
        Logging.shared.applyEnvironmentConfiguration(params.environment)

        // Bring up the core C++ bridges (platform adapter, events,
        // telemetry, device callbacks). Must run before Phase 1 proto so
        // every C++ log routes through SDKLogger and analytics callbacks
        // are wired up.
        CppBridge.initialize(environment: params.environment)

        let logger = SDKLogger(category: "RunAnywhere.Init")
        CppBridge.Events.emitSDKInitStarted()

        do {
            // Persist credentials (Apple-specific Keychain — must stay in Swift).
            if params.environment != .development {
                try KeychainManager.shared.storeSDKParams(params)
            }

            // Configure C++ model-paths base directory before any
            // registerModel() calls so rac_model_registry_save() can
            // reconcile entries against on-disk folders inline.
            if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                do {
                    try CppBridge.ModelPaths.setBaseDirectory(documentsURL)
                } catch {
                    logger.warning("Failed to set model paths base directory: \(error.localizedDescription)")
                }
            }

            // Phase 1 proto: validates inputs and runs rac_state_initialize.
            try CppBridge.SdkInit.phase1(
                environment: params.environment,
                apiKey: params.apiKey,
                baseURL: params.baseURL.absoluteString,
                deviceId: CppBridge.Device.persistentId
            )

            // SDK config (rac_sdk_init) + Keychain auth-storage install.
            // Idempotent state re-init is harmless; this call also wires up
            // version/platform metadata that Phase 1 proto does not touch.
            CppBridge.State.initialize(
                environment: params.environment,
                apiKey: params.apiKey,
                baseURL: params.baseURL,
                deviceId: CppBridge.Device.persistentId
            )

            isInitializedFlag = true

            let initDurationMs = (CFAbsoluteTimeGetCurrent() - initStartTime) * 1000
            logger.info("Phase 1 complete in \(String(format: "%.1f", initDurationMs))ms (\(params.environment.description))")
            CppBridge.Events.emitSDKInitCompleted(durationMs: initDurationMs)

            if startBackgroundServices {
                logger.debug("Starting Phase 2 (services) in background...")
                Task.detached(priority: .userInitiated) {
                    do {
                        try await completeServicesInitialization()
                        SDKLogger(category: "RunAnywhere.Init").info("Phase 2 complete (background)")
                    } catch {
                        SDKLogger(category: "RunAnywhere.Init")
                            .warning("Phase 2 failed (non-critical): \(error.localizedDescription)")
                    }
                }
            }

        } catch {
            logger.error("Initialization failed: \(error.localizedDescription)")
            initParams = nil
            isInitializedFlag = false
            CppBridge.Events.emitSDKInitFailed(error: SDKException.from(error))
            throw error
        }
    }

    // MARK: - Phase 2: Services Initialization (Async)

    /// Complete services initialization (Phase 2). Safe to call multiple
    /// times; concurrent callers share the same Task so the step list runs
    /// at most once.
    public static func completeServicesInitialization() async throws {
        if hasCompletedServicesInit { return }

        let task: Task<Void, Error> = _servicesInitLock.sync {
            if let existingTask = _servicesInitTask {
                return existingTask
            }
            let newTask = Task<Void, Error> { try await _performServicesInitialization() }
            _servicesInitTask = newTask
            return newTask
        }

        do {
            try await task.value
            _servicesInitLock.sync { _servicesInitTask = nil }
        } catch {
            _servicesInitLock.sync { _servicesInitTask = nil }
            throw error
        }
    }

    /// Phase 2 step list. Commons owns the deterministic orchestration
    /// (auth through the registered HTTP transport, device registration,
    /// assignment fetch, telemetry flush, and downloaded-model discovery).
    /// Swift retains only platform-service callback registration.
    private static func _performServicesInitialization() async throws {
        guard let params = initParams, let environment = currentEnvironment else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }

        let logger = SDKLogger(category: "RunAnywhere.Services")

        // Step 1: configure the Swift HTTP adapter used by callback-based
        // platform services. Auth and control-plane orchestration stay in C++.
        if await !CppBridge.HTTP.shared.isConfigured {
            if environment == .development {
                if await CppBridge.DevConfig.configureHTTP() {
                    logger.debug("HTTP adapter configured from C++ development config")
                } else {
                    logger.debug("HTTP adapter disabled: no usable development config")
                }
            } else if CppBridge.DevConfig.isUsableCredential(params.apiKey),
                      CppBridge.DevConfig.isUsableHTTPURL(params.baseURL.absoluteString) {
                await CppBridge.HTTP.shared.configure(baseURL: params.baseURL, apiKey: params.apiKey)
            } else {
                logger.debug("HTTP adapter disabled: no usable external config")
            }
        }

        // Step 2 (MainActor — must stay in Swift): platform-plugin and callback
        // registration. Commons uses these callbacks during Phase 2.
        await MainActor.run { CppBridge.initializeServices() }

        // Step 3 (C++): auth, device registration, model assignments,
        // telemetry flush, and downloaded-model discovery.
        let phase2Result = try CppBridge.SdkInit.phase2(
            buildToken: environment == .development ? CppBridge.DevConfig.buildToken : nil,
            forceRefreshAssignments: false,
            flushTelemetry: true,
            discoverDownloadedModels: true,
            rescanLocalModels: true
        )
        hasCompletedHTTPSetup = phase2Result.hasCompletedHTTPSetup_p || phase2Result.httpConfigured
        if !phase2Result.warning.isEmpty {
            logger.info("Phase 2 warning: \(phase2Result.warning)")
        }
        if phase2Result.linkedModelsCount > 0 {
            logger.info("Phase 2 linked \(phase2Result.linkedModelsCount) assigned models")
        }

        hasCompletedServicesInit = true
    }

    /// Ensure services are ready before API calls (internal guard).
    /// O(1) after first successful initialization with HTTP configured.
    /// If core services are done but HTTP/auth failed (offline init), retries auth only.
    internal static func ensureServicesReady() async throws {
        if hasCompletedServicesInit && hasCompletedHTTPSetup {
            return
        }
        if hasCompletedServicesInit && !hasCompletedHTTPSetup {
            await retryHTTPSetup()
            return
        }
        try await completeServicesInitialization()
    }

    /// Retry HTTP/auth after an offline initialization. Commons performs the
    /// round-trip through the registered platform HTTP transport.
    private static func retryHTTPSetup() async {
        guard currentEnvironment != nil else { return }
        let logger = SDKLogger(category: "RunAnywhere.HTTPRetry")

        let proto: RASdkInitResult
        do {
            proto = try CppBridge.SdkInit.retryHTTP()
        } catch {
            logger.debug("HTTP retry proto failed: \(error.localizedDescription)")
            return
        }

        hasCompletedHTTPSetup = proto.hasCompletedHTTPSetup_p || proto.httpConfigured

        if !proto.warning.isEmpty {
            logger.debug("HTTP retry warning: \(proto.warning)")
        }

        if hasCompletedHTTPSetup {
            logger.info("HTTP/Auth setup succeeded on retry")
        }
    }
}
