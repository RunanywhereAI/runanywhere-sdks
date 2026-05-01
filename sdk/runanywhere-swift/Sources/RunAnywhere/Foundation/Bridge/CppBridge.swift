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
 *   ├─ ModelAssignment.register()  ← Model assignment callbacks
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
 * - CppBridge+Services.swift - Service registry
 * - CppBridge+ModelPaths.swift - Model path utilities
 * - CppBridge+ModelRegistry.swift - Model registry
 * - CppBridge+ModelAssignment.swift - Model assignment
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
    /// `OSAllocatedUnfairLock`. Replaces the prior NSLock + 3 vars layout
    /// per CLAUDE.md "Do not use NSLock as it is outdated."
    private struct CppBridgeSharedState {
        var environment: SDKEnvironment = .development
        var isInitialized: Bool = false
        var servicesInitialized: Bool = false
    }

    private static let state =
        OSAllocatedUnfairLock<CppBridgeSharedState>(initialState: CppBridgeSharedState())

    /// Current SDK environment
    static var environment: SDKEnvironment {
        state.withLock { $0.environment }
    }

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
        let alreadyInitialized = state.withLock { s -> Bool in
            if s.isInitialized { return true }
            s.environment = environment
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

        // Step 2: Events callback (for analytics routing)
        Events.register()

        // Step 3: Telemetry manager (builds JSON, calls HTTP callback)
        Telemetry.initialize(environment: environment)

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
        let snapshot = state.withLock { s -> (alreadyDone: Bool, env: SDKEnvironment) in
            (s.servicesInitialized, s.environment)
        }
        guard !snapshot.alreadyDone else { return }
        let currentEnv = snapshot.env

        // Model assignment (needs HTTP for API calls)
        // Only auto-fetch in staging/production, not development
        // IMPORTANT: Register WITHOUT auto-fetch first to avoid MainActor deadlock
        // The HTTP callback uses semaphore.wait() which would block MainActor
        // while the Task{} inside needs MainActor access
        let shouldAutoFetch = currentEnv != .development
        ModelAssignment.register(autoFetch: false)

        // If auto-fetch is needed, trigger it asynchronously off MainActor
        if shouldAutoFetch {
            Task.detached {
                do {
                    _ = try await ModelAssignment.fetch(forceRefresh: true)
                    SDKLogger(category: "CppBridge").info("Auto-fetched model assignments successfully")
                } catch {
                    SDKLogger(category: "CppBridge").warning("Auto-fetch model assignments failed: \(error.localizedDescription)")
                }
            }
        }

        // Platform services (Foundation Models, System TTS)
        Platform.register()

        state.withLock { $0.servicesInitialized = true }

        SDKLogger(category: "CppBridge").debug("Service bridges initialized (env: \(currentEnv), autoFetch: \(shouldAutoFetch))")
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
        // Note: ModelAssignment and Platform callbacks remain valid (static)

        Telemetry.shutdown()
        Events.unregister()
        // PlatformAdapter callbacks remain valid (static)
        // Device callbacks remain valid (static)

        state.withLock {
            $0.isInitialized = false
            $0.servicesInitialized = false
        }

        SDKLogger(category: "CppBridge").debug("All bridges shutdown")
    }
}
