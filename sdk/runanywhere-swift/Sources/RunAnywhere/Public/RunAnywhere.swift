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

/// Monotonic lifetime state shared by synchronous initialization and async
/// reset. A generation prevents a stale reset completion from reopening a
/// newer SDK lifetime.
struct SDKLifetimeGate: Sendable {
    private(set) var generation: UInt64 = 0
    private(set) var isResetInProgress = false

    mutating func beginReset() -> UInt64? {
        guard !isResetInProgress else { return nil }
        generation &+= 1
        isResetInProgress = true
        return generation
    }

    @discardableResult
    mutating func completeReset(generation completedGeneration: UInt64) -> Bool {
        guard isResetInProgress, generation == completedGeneration else { return false }
        isResetInProgress = false
        return true
    }

    func requireInitializationAllowed() throws {
        guard !isResetInProgress else {
            throw SDKException(
                code: .invalidState,
                message: "SDK reset is in progress; retry initialization after reset completes",
                category: .internal
            )
        }
    }

    func permitsCompletion(generation candidate: UInt64) -> Bool {
        !isResetInProgress && generation == candidate
    }
}

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
        var httpRetryTask: Task<Void, Never>?
        var httpRetryTaskID: UInt64?
        var nextHTTPRetryTaskID: UInt64 = 0
        var resetTask: Task<Void, Never>?
        var lifetime = SDKLifetimeGate()
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
    public static var deviceId: String {
        get throws { try CppBridge.Device.persistentId }
    }

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

        let task = await beginReset()
        await task.value

        logger.info("SDK state reset completed")
    }

    /// Linearize reset with synchronous Phase 1 without blocking the caller's
    /// actor. Concurrent reset callers share the same teardown task.
    private static func beginReset() async -> Task<Void, Never> {
        await withCheckedContinuation { continuation in
            coreInitQueue.async {
                let task = state.withLock { lockedState -> Task<Void, Never> in
                    if let existingTask = lockedState.resetTask {
                        return existingTask
                    }

                    guard let generation = lockedState.lifetime.beginReset() else {
                        preconditionFailure("reset lifetime has no owning task")
                    }

                    let servicesTask = lockedState.servicesInitTask
                    let httpRetryTask = lockedState.httpRetryTask
                    lockedState.initParams = nil
                    lockedState.currentEnvironment = nil
                    lockedState.isInitialized = false
                    lockedState.hasCompletedServicesInit = false
                    lockedState.hasCompletedHTTPSetup = false
                    lockedState.httpSetupApplicable = true
                    lockedState.servicesInitTask = nil
                    lockedState.httpRetryTask = nil
                    lockedState.httpRetryTaskID = nil

                    let resetTask = Task.detached(priority: .userInitiated) {
                        servicesTask?.cancel()
                        httpRetryTask?.cancel()
                        if let servicesTask {
                            _ = await servicesTask.result
                        }
                        if let httpRetryTask {
                            await httpRetryTask.value
                        }

                        await CppBridge.shutdown()

                        state.withLock { completedState in
                            guard completedState.lifetime.completeReset(
                                generation: generation
                            ) else { return }
                            let lifetime = completedState.lifetime
                            completedState = SDKState(lifetime: lifetime)
                        }
                    }
                    lockedState.resetTask = resetTask
                    return resetTask
                }
                continuation.resume(returning: task)
            }
        }
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
        let alreadyInitialized = try state.withLock { lockedState -> Bool in
            try lockedState.lifetime.requireInitializationAllowed()
            return lockedState.isInitialized
        }
        guard !alreadyInitialized else { return }

        let initStartTime = CFAbsoluteTimeGetCurrent()

        // Set environment first so logging boots with correct config.
        state.withLock {
            $0.currentEnvironment = params.environment
            $0.initParams = params
            $0.hasCompletedServicesInit = false
            $0.hasCompletedHTTPSetup = false
            $0.httpSetupApplicable = true
            $0.servicesInitTask = nil
            $0.httpRetryTask = nil
            $0.httpRetryTaskID = nil
        }
        Logging.shared.applyEnvironmentConfiguration(params.environment)

        // Lifecycle INITIALIZATION_STAGE_* events (incl. duration_ms) are
        // published once by commons from rac_sdk_init_phase1_proto; Swift no
        // longer hand-emits duplicates.
        let logger = SDKLogger(category: "RunAnywhere.Init")

        do {
            // Bring up the core C++ bridges and durably resolve device identity
            // before Phase 1 can consume it.
            try CppBridge.initialize(environment: params.environment)

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
            let deviceId = try CppBridge.Device.persistentId
            try CppBridge.SdkInit.phase1(
                environment: params.environment,
                apiKey: params.apiKey,
                baseURL: params.baseURL.absoluteString,
                deviceId: deviceId
            )

            // SDK config (rac_sdk_init) + Keychain auth-storage install.
            // Idempotent state re-init is harmless; this call also wires up
            // version/platform metadata that Phase 1 proto does not touch.
            try CppBridge.State.initialize(
                environment: params.environment,
                apiKey: params.apiKey,
                baseURL: params.baseURL,
                deviceId: deviceId
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
            // Phase 1 may have initialized native state and synchronous bridge
            // services before a later validation or Keychain restore failed.
            // Roll both layers back so a retry can use a different environment
            // and reinstall auth storage instead of inheriting partial state.
            // CppBridge.initialize() owns rollback for its own failure path;
            // later Phase-1 failures arrive with the bridge still initialized.
            if CppBridge.isInitialized {
                CppBridge.rollbackInitialization()
            }
            state.withLock {
                $0.initParams = nil
                $0.currentEnvironment = nil
                $0.isInitialized = false
                $0.hasCompletedServicesInit = false
                $0.hasCompletedHTTPSetup = false
                $0.httpSetupApplicable = true
                $0.servicesInitTask = nil
                $0.httpRetryTask = nil
                $0.httpRetryTaskID = nil
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

        let task: Task<Void, Error> = try state.withLock { lockedState in
            try lockedState.lifetime.requireInitializationAllowed()
            guard lockedState.isInitialized else {
                throw SDKException(
                    code: .notInitialized,
                    message: "SDK not initialized",
                    category: .internal
                )
            }
            if let existingTask = lockedState.servicesInitTask {
                return existingTask
            }
            let newTask = Task<Void, Error> { try await _performServicesInitialization() }
            lockedState.servicesInitTask = newTask
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
            } else {
                // Effective config from commons state: staging overrides
                // whatever the app passed (baked URL, keyless).
                let effectiveURLString = CppBridge.State.baseURL ?? params.baseURL.absoluteString
                if CppBridge.DevConfig.isUsableHTTPURL(effectiveURLString),
                   let effectiveURL = URL(string: effectiveURLString) {
                    await CppBridge.HTTP.shared.configure(baseURL: effectiveURL, apiKey: params.apiKey)
                } else {
                    logger.debug("HTTP adapter disabled: no usable external config")
                }
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
            logger.info("Phase 2 completed with a warning; details omitted")
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
        let operation: (id: UInt64, generation: UInt64, task: Task<Void, Never>)? =
            state.withLock { lockedState in
                guard !lockedState.lifetime.isResetInProgress,
                      lockedState.isInitialized,
                      lockedState.currentEnvironment != nil else {
                    return nil
                }
                if let task = lockedState.httpRetryTask,
                   let id = lockedState.httpRetryTaskID {
                    return (id, lockedState.lifetime.generation, task)
                }

                lockedState.nextHTTPRetryTaskID &+= 1
                let id = lockedState.nextHTTPRetryTaskID
                let generation = lockedState.lifetime.generation
                let task = Task.detached(priority: .userInitiated) {
                    await performHTTPRetry(generation: generation)
                }
                lockedState.httpRetryTask = task
                lockedState.httpRetryTaskID = id
                return (id, generation, task)
            }
        guard let operation else { return }

        await operation.task.value
        state.withLock { lockedState in
            guard lockedState.lifetime.permitsCompletion(generation: operation.generation),
                  lockedState.httpRetryTaskID == operation.id else {
                return
            }
            lockedState.httpRetryTask = nil
            lockedState.httpRetryTaskID = nil
        }
    }

    private static func performHTTPRetry(generation: UInt64) async {
        guard !Task.isCancelled else { return }
        let canStart = state.withLock { lockedState in
            lockedState.lifetime.permitsCompletion(generation: generation) &&
                lockedState.isInitialized && lockedState.currentEnvironment != nil
        }
        guard canStart else { return }

        let logger = SDKLogger(category: "RunAnywhere.HTTPRetry")

        let proto: RASdkInitResult
        do {
            proto = try CppBridge.SdkInit.retryHTTP()
        } catch {
            logger.debug("HTTP retry failed")
            return
        }

        guard !Task.isCancelled else { return }
        let completedHTTPSetup = proto.hasCompletedHTTPSetup_p || proto.httpConfigured
        let committed = state.withLock { lockedState -> Bool in
            guard lockedState.lifetime.permitsCompletion(generation: generation),
                  lockedState.isInitialized else {
                return false
            }
            lockedState.hasCompletedHTTPSetup = completedHTTPSetup
            lockedState.httpSetupApplicable = proto.httpApplicable
            return true
        }
        guard committed else { return }

        if !proto.warning.isEmpty {
            logger.debug("HTTP retry completed with a warning; details omitted")
        }

        if completedHTTPSetup {
            logger.info("HTTP/Auth setup succeeded on retry")
        }
    }
}
