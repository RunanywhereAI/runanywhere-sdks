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
 * Phase 1 (sync, must run first): `CppBridge.initialize(environment:)` calls
 * PlatformAdapter.register() (file ops, logging, keychain), Events.register()
 * (analytics event callback), Telemetry.initialize() (telemetry HTTP callback),
 * and Device.register() (device registration callbacks).
 *
 * Phase 2 (async, after HTTP is configured): `await CppBridge.initializeServices()`
 * calls Platform.register() (LLM/TTS service callbacks).
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

/// Central coordinator for all C++ bridges
/// Manages lifecycle and shared resources
public enum CppBridge {

    // MARK: - Shared State

    /// Combined synchronously-readable bridge state, guarded by a single
    /// `OSAllocatedUnfairLock` (not NSLock, per AGENTS.md).
    private struct CppBridgeSharedState {
        var environment: SDKEnvironment = .development
        var isInitialized: Bool = false
        var servicesInitialized: Bool = false
    }

    private static let state =
        OSAllocatedUnfairLock<CppBridgeSharedState>(initialState: CppBridgeSharedState())

    /// Whether core bridges are initialized (Phase 1)
    public static var isInitialized: Bool {
        state.withLock { $0.isInitialized }
    }

    /// Whether service bridges are initialized (Phase 2)
    public static var servicesInitialized: Bool {
        state.withLock { $0.servicesInitialized }
    }

    // MARK: - Phase 1: Core Initialization (Synchronous)

    /// Initialize all core C++ bridges
    ///
    /// This must be called FIRST during SDK initialization, before any C++ operations.
    /// It registers fundamental platform callbacks that C++ needs.
    ///
    /// - Parameter environment: SDK environment
    public static func initialize(environment: SDKEnvironment) {
        let alreadyInitialized = state.withLock { current -> Bool in
            if current.isInitialized { return true }
            current.environment = environment
            return false
        }
        guard !alreadyInitialized else { return }

        // Step 1: Platform adapter FIRST (logging, file ops, keychain)
        // This must be registered before any other C++ calls
        PlatformAdapter.register()

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

        // Step 2: Telemetry manager (builds JSON, calls HTTP callback).
        // Must come before Events.register(): the events bridge attaches this
        // manager to the C++ router as the telemetry sink, so the manager has
        // to exist first.
        Telemetry.initialize(environment: environment)

        // Step 3: Attach the telemetry manager as the C++ router's telemetry sink.
        Events.register()

        // Step 3.5: Start the EventBus native subscription so lifecycle/model/
        // error events flow into `EventBus.shared.events` (see EventBus.start()).
        EventBus.shared.start()

        // Step 4: Device registration callbacks
        Device.register()

        state.withLock { $0.isInitialized = true }

        SDKLogger(category: "CppBridge").debug("Core bridges initialized for \(environment)")
    }

    // MARK: - Phase 2: Services Initialization (Async)

    /// Initialize service bridges that require HTTP
    ///
    /// Called after HTTP transport is configured. These bridges need
    /// network access to function.
    @MainActor
    public static func initializeServices() {
        let snapshot = state.withLock { current -> (alreadyDone: Bool, env: SDKEnvironment) in
            (current.servicesInitialized, current.environment)
        }
        guard !snapshot.alreadyDone else { return }
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
        let wasInitialized = state.withLock { $0.isInitialized }
        guard wasInitialized else { return }

        // Destroy AI components sequentially before tearing down Telemetry/Events
        await LLM.shared.destroy()
        await STT.shared.destroy()
        await TTS.shared.destroy()
        await VAD.shared.destroy()
        await VoiceAgent.shared.destroy()
        await VLM.shared.destroy()

        // Shutdown in reverse order
        // Note: Platform callbacks remain valid (static)

        // Stop the EventBus native subscription while the native ABI surface
        // is still alive (see EventBus.stop()).
        EventBus.shared.stop()

        // Detach the router's telemetry sink BEFORE destroying the manager so
        // the C++ router never holds a dangling manager pointer.
        Events.unregister()
        Telemetry.shutdown()
        // PlatformAdapter callbacks remain valid (static)
        // Device callbacks remain valid (static)

        state.withLock {
            $0.isInitialized = false
            $0.servicesInitialized = false
        }

        SDKLogger(category: "CppBridge").debug("All bridges shutdown")
    }
}
