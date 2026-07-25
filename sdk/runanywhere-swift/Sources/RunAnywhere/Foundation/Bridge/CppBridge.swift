/**
 * CppBridge.swift
 *
 * Unified bridge architecture for C++ ↔ Swift interop.
 *
 * All C++ bridges are organized under a single namespace for:
 * - Consistent initialization/shutdown lifecycle
 * - Shared access to platform resources
 * - Clear ownership and dependency management
 *
 * ## Initialization Order
 *
 * ```swift
 * // Phase 1: Core init (sync) - must be called first
 * CppBridge.initialize(environment: .production)
 *   ├─ PlatformAdapter.register()  ← File ops, logging, keychain
 *   ├─ Events.register()           ← Analytics event callback
 *   ├─ Telemetry.initialize()      ← Telemetry HTTP callback
 *   └─ Device.register()           ← Device registration callbacks
 *
 * // Phase 2: Services init (async) - after HTTP is configured
 * await CppBridge.initializeServices()
 *   └─ Platform.register()         ← LLM/TTS service callbacks
 * ```
 *
 * ## Bridge Extensions (in Extensions/ folder)
 *
 * - CppBridge+PlatformAdapter.swift - File ops, logging, keychain, clock
 * - CppBridge+Environment.swift - Environment, DevConfig, Endpoints
 * - CppBridge+Telemetry.swift - Events, Telemetry
 * - CppBridge+Device.swift - Device registration
 * - CppBridge+State.swift - SDK state management
 * - CppBridge+HTTP.swift - HTTP transport
 * - CppBridge+Auth.swift - Authentication flow
 * - CppBridge+ModelPaths.swift - Model path utilities
 * - CppBridge+ModelRegistry.swift - Model registry
 * - CppBridge+Download.swift - Download manager
 * - CppBridge+Platform.swift - Platform services (Foundation Models, System TTS)
 * - CppBridge+LLM/STT/TTS/VAD.swift - AI component bridges
 * - CppBridge+VoiceAgent.swift - Voice agent bridge
 * - CppBridge+Storage/Strategy.swift - Storage utilities
 */

import CRACommons
import Foundation
import os

// MARK: - Main Bridge Coordinator

struct CppBridgeLifetimeGate: Sendable {
    enum Phase: Sendable, Equatable {
        case idle
        case initializing
        case initialized
        case shuttingDown
    }

    enum ShutdownAdmission: Sendable, Equatable {
        case notNeeded
        case waitForInitialization
        case start
        case join
    }

    private(set) var phase: Phase = .idle

    var isInitialized: Bool { phase == .initialized }

    mutating func beginInitialization() throws -> Bool {
        switch phase {
        case .idle:
            phase = .initializing
            return true
        case .initialized:
            return false
        case .initializing, .shuttingDown:
            throw SDKException(
                code: .invalidState,
                message: "C++ bridge lifecycle transition is in progress",
                category: .internal
            )
        }
    }

    @discardableResult
    mutating func completeInitialization() -> Bool {
        guard phase == .initializing else { return false }
        phase = .initialized
        return true
    }

    mutating func beginRollback() -> Bool {
        guard phase == .initializing || phase == .initialized else { return false }
        phase = .shuttingDown
        return true
    }

    mutating func beginShutdown() -> ShutdownAdmission {
        switch phase {
        case .idle:
            return .notNeeded
        case .initializing:
            return .waitForInitialization
        case .initialized:
            phase = .shuttingDown
            return .start
        case .shuttingDown:
            return .join
        }
    }

    @discardableResult
    mutating func completeShutdown() -> Bool {
        guard phase == .shuttingDown else { return false }
        phase = .idle
        return true
    }
}

/// Central coordinator for all C++ bridges
/// Manages lifecycle and shared resources
public enum CppBridge {

    // MARK: - Shared State

    /// Combined synchronously-readable bridge state, guarded by a single
    /// `OSAllocatedUnfairLock`. Replaces the prior NSLock + 3 vars layout
    /// per AGENTS.md "Do not use NSLock as it is outdated."
    private struct CppBridgeSharedState {
        var environment: SDKEnvironment = .development
        var servicesInitialized: Bool = false
        var lifecycle = CppBridgeLifetimeGate()
        var shutdownTask: Task<Void, Never>?
    }

    private static let state =
        OSAllocatedUnfairLock<CppBridgeSharedState>(initialState: CppBridgeSharedState())

    /// Whether core bridges are initialized (Phase 1)
    public static var isInitialized: Bool {
        state.withLock { $0.lifecycle.isInitialized }
    }

    /// Whether service bridges are initialized (Phase 2)
    public static var servicesInitialized: Bool {
        state.withLock { $0.lifecycle.isInitialized && $0.servicesInitialized }
    }

    // MARK: - Phase 1: Core Initialization (Synchronous)

    /// Initialize all core C++ bridges
    ///
    /// This must be called FIRST during SDK initialization, before any C++ operations.
    /// It registers fundamental platform callbacks that C++ needs.
    ///
    /// - Parameter environment: SDK environment
    public static func initialize(environment: SDKEnvironment) throws {
        let shouldInitialize = try state.withLock { current -> Bool in
            let admitted = try current.lifecycle.beginInitialization()
            if admitted {
                current.environment = environment
            }
            return admitted
        }
        guard shouldInitialize else { return }

        do {
            // Step 1: Platform adapter FIRST (logging, file ops, keychain)
            // This must be registered before any other C++ calls
            PlatformAdapter.register()
            let deviceId = try Device.persistentId

            // Step 1.1: Register the Swift URLSession HTTP transport so
            // every subsequent `rac_http_request_*` call flows through
            // Apple's stack (trust store, ATS, proxies, HTTP/2). Must
            // happen before any other bridge that might trigger HTTP —
            // e.g. Telemetry initialization below.
            URLSessionHttpTransport.register()

            // Step 1.5: Configure C++ logging based on environment
            // In production: disables C++ stderr, logs only go through Swift bridge
            // In development: C++ stderr ON for debugging
            rac_configure_logging(environment.cEnvironment)

            // Step 1.6: Host app/client metadata. `platform` remains the OS
            // family; this separate structured payload carries the SDK binding and
            // Bundle facts for device registration.
            ClientInfo.register()

            // Step 2: Telemetry manager (builds JSON, calls HTTP callback).
            // Must come before Events.register(): the events bridge attaches this
            // manager to the C++ router as the telemetry sink, so the manager has
            // to exist first.
            Telemetry.initialize(environment: environment, deviceId: deviceId)

            // Step 3: Attach the telemetry manager as the C++ router's telemetry sink.
            Events.register()

            // Step 3.5: Start the EventBus native subscription so lifecycle/model/
            // error events flow into `EventBus.shared.events` (see EventBus.start()).
            EventBus.shared.start()

            // Step 4: Device registration callbacks
            try Device.register()

            let committed = state.withLock { $0.lifecycle.completeInitialization() }
            guard committed else {
                throw SDKException(
                    code: .invalidState,
                    message: "C++ bridge initialization lost lifecycle ownership",
                    category: .internal
                )
            }

            SDKLogger(category: "CppBridge").debug("Core bridges initialized for \(environment)")
        } catch {
            rollbackInitialization()
            throw error
        }
    }

    /// Tear down synchronous Phase-1 bridge state after a failed initialization.
    /// Safe before `isInitialized` is committed and safe to call repeatedly.
    static func rollbackInitialization() {
        let ownsRollback = state.withLock { current -> Bool in
            guard current.shutdownTask == nil else { return false }
            return current.lifecycle.beginRollback()
        }
        guard ownsRollback else { return }

        Device.unregister()
        // Canonical native shutdown publishes its lifecycle event and clears
        // Commons state while logging/event/platform dependencies still exist.
        State.shutdown()
        EventBus.shared.stop()
        Events.unregister()
        Telemetry.rollbackInitialization()
        URLSessionHttpTransport.unregister()
        PlatformAdapter.unregister()
        state.withLock {
            $0.environment = .development
            $0.servicesInitialized = false
            _ = $0.lifecycle.completeShutdown()
        }
    }

    // MARK: - Phase 2: Services Initialization (Async)

    /// Initialize service bridges that require HTTP
    ///
    /// Called after HTTP transport is configured. These bridges need
    /// network access to function.
    @MainActor
    public static func initializeServices() {
        let snapshot = state.withLock { current -> (active: Bool, alreadyDone: Bool, env: SDKEnvironment) in
            (current.lifecycle.isInitialized, current.servicesInitialized, current.environment)
        }
        guard snapshot.active, !snapshot.alreadyDone else { return }
        let currentEnv = snapshot.env

        // Model assignment fetch needs no Swift callbacks: commons routes it
        // through the registered URLSession HTTP transport, and the fetch
        // itself is owned by rac_sdk_init_phase2_proto.

        // Platform services (Foundation Models, System TTS)
        Platform.register()

        state.withLock { $0.servicesInitialized = true }

        SDKLogger(category: "CppBridge").debug("Service bridges initialized (env: \(currentEnv))")
    }

    // MARK: - Shutdown

    /// Shutdown all C++ bridges
    ///
    /// Async because AI component destroy() methods are actor-isolated.
    /// Awaiting them sequentially (instead of wrapping in `Task { ... }`)
    /// ensures Telemetry/Events teardown does not race destroy completion.
    public static func shutdown() async {
        while true {
            let decision = state.withLock { current -> ShutdownDecision in
                switch current.lifecycle.beginShutdown() {
                case .notNeeded:
                    return .complete
                case .waitForInitialization:
                    return .wait
                case .start:
                    let task = Task.detached(priority: .userInitiated) {
                        await performShutdown()
                    }
                    current.shutdownTask = task
                    return .join(task)
                case .join:
                    if let task = current.shutdownTask {
                        return .join(task)
                    }
                    return .wait
                }
            }

            switch decision {
            case .complete:
                return
            case .wait:
                await Task.yield()
            case let .join(task):
                await task.value
                return
            }
        }
    }

    private enum ShutdownDecision {
        case complete
        case wait
        case join(Task<Void, Never>)
    }

    private static func performShutdown() async {

        // Destroy AI components sequentially before tearing down Telemetry/Events
        await LLM.shared.destroy()
        await STT.shared.destroy()
        await TTS.shared.destroy()
        await VAD.shared.destroy()
        await Diarization.shared.destroy()
        await VoiceAgent.shared.destroy()

        await MainActor.run {
            Platform.unregister()
        }

        Device.unregister()

        // Canonical native shutdown must run exactly once before its borrowed
        // platform adapter and event/log dependencies are detached.
        State.shutdown()

        // Stop the EventBus native subscription while the native ABI surface
        // is still alive (see EventBus.stop()).
        EventBus.shared.stop()

        // Detach the router's telemetry sink BEFORE destroying the manager so
        // the C++ router never holds a dangling manager pointer.
        Events.unregister()
        await Telemetry.shutdown()
        await HTTPClientAdapter.shared.shutdown()
        URLSessionHttpTransport.unregister()
        PlatformAdapter.unregister()

        state.withLock {
            $0.environment = .development
            $0.servicesInitialized = false
            $0.shutdownTask = nil
            _ = $0.lifecycle.completeShutdown()
        }

        SDKLogger(category: "CppBridge").debug("All bridges shutdown")
    }
}
