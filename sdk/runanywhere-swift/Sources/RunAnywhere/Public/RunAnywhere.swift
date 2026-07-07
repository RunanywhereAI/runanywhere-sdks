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
//    * Task.detached spawning + Swift-side initialization state
//    * Keychain SDK params persistence (Apple-specific)
//    * MainActor platform-plugin/callback registration
//    * URLSession HTTP transport implementation and adapter configuration
//

import Darwin
import Foundation
import os

/// The RunAnywhere SDK - Single entry point for on-device AI
public enum RunAnywhere {

    // MARK: - Internal State Management

    private struct SDKState: @unchecked Sendable {
        var initParams: SDKInitParams?
        var currentEnvironment: SDKEnvironment?
        var isInitialized = false
        var hasCompletedServicesInit = false
        var hasCompletedHTTPSetup = false
        var httpSetupApplicable = true
        var servicesInitTask: Task<Void, Error>?
    }

    private static let state = OSAllocatedUnfairLock<SDKState>(initialState: SDKState())

    /// Serializes Phase 1 core initialization so concurrent `initialize()`
    /// callers cannot both enter the C++ bridge setup path.
    private static let coreInitQueue = DispatchQueue(label: "com.runanywhere.sdk.coreInit")

    /// Internal init params storage.
    internal static var initParams: SDKInitParams? { state.withLock { $0.initParams } }
    internal static var currentEnvironment: SDKEnvironment? { state.withLock { $0.currentEnvironment } }
    internal static var isInitializedFlag: Bool { state.withLock { $0.isInitialized } }

    /// Track if services initialization is complete (makes API calls O(1) after first use).
    internal static var hasCompletedServicesInit: Bool { state.withLock { $0.hasCompletedServicesInit } }
    /// Track if HTTP/auth setup succeeded (separate from core services so auth can be retried on reconnect).
    internal static var hasCompletedHTTPSetup: Bool { state.withLock { $0.hasCompletedHTTPSetup } }
    internal static var isLocalOnlyMode: Bool {
        guard let rawValue = getenv("RUNANYWHERE_SWIFT_LOCAL_ONLY") else {
            return false
        }
        let value = String(cString: rawValue).lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    // MARK: - SDK State

    /// Check if SDK is initialized (Phase 1 complete).
    public static var isInitialized: Bool { isInitializedFlag }

    /// Check if services are fully ready (Phase 2 complete)
    public static var areServicesReady: Bool { hasCompletedServicesInit }

    /// Check if SDK is active and ready for use
    public static var isActive: Bool {
        state.withLock { $0.isInitialized && $0.initParams != nil }
    }

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

        let taskToCancel = state.withLock { lockedState -> Task<Void, Error>? in
            let task = lockedState.servicesInitTask
            lockedState = SDKState()
            return task
        }
        taskToCancel?.cancel()

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
        try coreInitQueue.sync {
            try performCoreInitSerial(with: params, startBackgroundServices: startBackgroundServices)
        }
    }

    private static func performCoreInitSerial(with params: SDKInitParams, startBackgroundServices: Bool) throws {
        guard !isInitializedFlag else { return }

        let initStartTime = CFAbsoluteTimeGetCurrent()

        // Set environment first so logging boots with correct config.
        state.withLock {
            $0.currentEnvironment = params.environment
            $0.initParams = params
            $0.hasCompletedServicesInit = false
            $0.hasCompletedHTTPSetup = false
            $0.httpSetupApplicable = true
            $0.servicesInitTask = nil
        }
        Logging.shared.applyEnvironmentConfiguration(params.environment)

        // Bring up the core C++ bridges (platform adapter, events,
        // telemetry, device callbacks). Must run before Phase 1 proto so
        // every C++ log routes through SDKLogger and analytics callbacks
        // are wired up.
        CppBridge.initialize(environment: params.environment)

        // Lifecycle INITIALIZATION_STAGE_* events (incl. duration_ms) are
        // published once by commons from rac_sdk_init_phase1_proto; Swift no
        // longer hand-emits duplicates.
        let logger = SDKLogger(category: "RunAnywhere.Init")

        do {
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

            state.withLock { $0.isInitialized = true }

            let initDurationMs = (CFAbsoluteTimeGetCurrent() - initStartTime) * 1000
            logger.info("Phase 1 complete in \(String(format: "%.1f", initDurationMs))ms (\(params.environment.description))")

            if isLocalOnlyMode {
                state.withLock {
                    $0.hasCompletedServicesInit = true
                    $0.hasCompletedHTTPSetup = false
                    $0.httpSetupApplicable = false
                }
                logger.debug("Phase 2 skipped for local-only Swift process")
            } else if startBackgroundServices {
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
            state.withLock {
                $0.initParams = nil
                $0.currentEnvironment = nil
                $0.isInitialized = false
                $0.hasCompletedServicesInit = false
                $0.hasCompletedHTTPSetup = false
                $0.httpSetupApplicable = true
                $0.servicesInitTask = nil
            }
            throw error
        }
    }

    // MARK: - Phase 2: Services Initialization (Async)

    /// Complete services initialization (Phase 2). Safe to call multiple
    /// times; concurrent callers share the same Task so the step list runs
    /// at most once.
    public static func completeServicesInitialization() async throws {
        if hasCompletedServicesInit { return }

        let task: Task<Void, Error> = state.withLock {
            if let existingTask = $0.servicesInitTask {
                return existingTask
            }
            let newTask = Task<Void, Error> { try await _performServicesInitialization() }
            $0.servicesInitTask = newTask
            return newTask
        }

        do {
            try await task.value
            state.withLock { $0.servicesInitTask = nil }
        } catch {
            state.withLock { $0.servicesInitTask = nil }
            throw error
        }
    }

    /// Phase 2 step list. Commons owns the deterministic orchestration
    /// (auth through the registered HTTP transport, device registration,
    /// assignment fetch, telemetry flush, and downloaded-model discovery).
    /// Swift retains only platform-service callback registration.
    private static func _performServicesInitialization() async throws {
        let snapshot = state.withLock { ($0.initParams, $0.currentEnvironment) }
        guard let params = snapshot.0, let environment = snapshot.1 else {
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
        let completedHTTPSetup = phase2Result.hasCompletedHTTPSetup_p || phase2Result.httpConfigured
        if !phase2Result.warning.isEmpty {
            logger.info("Phase 2 warning: \(phase2Result.warning)")
        }
        if phase2Result.linkedModelsCount > 0 {
            logger.info("Phase 2 linked \(phase2Result.linkedModelsCount) assigned models")
        }

        state.withLock {
            $0.hasCompletedHTTPSetup = completedHTTPSetup
            $0.httpSetupApplicable = phase2Result.httpApplicable
            $0.hasCompletedServicesInit = true
        }
    }

    /// Ensure services are ready before API calls (internal guard).
    /// O(1) after first successful initialization with HTTP configured.
    /// If core services are done but HTTP/auth failed (offline init), retries auth only.
    internal static func ensureServicesReady() async throws {
        if isLocalOnlyMode && isInitializedFlag {
            return
        }

        let readiness = state.withLock {
            (
                services: $0.hasCompletedServicesInit,
                http: $0.hasCompletedHTTPSetup,
                applicable: $0.httpSetupApplicable
            )
        }
        if readiness.services && (readiness.http || !readiness.applicable) {
            return
        }
        if readiness.services && !readiness.http && readiness.applicable {
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

        let completedHTTPSetup = proto.hasCompletedHTTPSetup_p || proto.httpConfigured
        state.withLock {
            $0.hasCompletedHTTPSetup = completedHTTPSetup
            $0.httpSetupApplicable = proto.httpApplicable
        }

        if !proto.warning.isEmpty {
            logger.debug("HTTP retry warning: \(proto.warning)")
        }

        if completedHTTPSetup {
            logger.info("HTTP/Auth setup succeeded on retry")
        }
    }
}
