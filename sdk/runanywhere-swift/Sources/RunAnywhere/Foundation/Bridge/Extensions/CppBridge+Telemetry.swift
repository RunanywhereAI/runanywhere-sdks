//
//  CppBridge+Telemetry.swift
//  RunAnywhere SDK
//
//  Telemetry bridge for C++ interop.
//  All events originate from C++ - Swift only provides HTTP transport.
//

import CRACommons
import Foundation
import os

// MARK: - Sendable Wrappers

/// Wraps the opaque telemetry-manager pointer so it can cross
/// closure/actor boundaries under Swift 6 strict concurrency.
/// `OpaquePointer` itself is not `Sendable`; the C++ side owns the
/// lifetime, so we explicitly opt in via `@unchecked Sendable`.
private struct ManagerHandle: @unchecked Sendable {
    let ptr: OpaquePointer
}

// MARK: - Events Bridge

extension CppBridge {

    /// Analytics events bridge
    /// C++ handles all event logic - Swift just handles HTTP transport
    public enum Events {

        private static var isRegistered = false

        /// Register the C++ telemetry sink.
        ///
        /// The C++ destination-bitmask router (`rac::events::route`) now drives
        /// telemetry internally: it calls `rac_telemetry_manager_track_proto`
        /// for every event whose destination carries the TELEMETRY bit. Swift
        /// only has to attach the telemetry manager once as the sink — there is
        /// no per-event analytics callback to translate anymore.
        static func register() {
            guard !isRegistered else { return }

            guard let mgr = CppBridge.Telemetry.handle else {
                SDKLogger(category: "CppBridge.Events").warning(
                    "Telemetry manager not initialized; skipping telemetry sink registration"
                )
                return
            }

            // Attach the telemetry manager as the router's telemetry sink.
            // `rac_events_set_telemetry_sink` takes the manager as an opaque
            // `void*` (NULL to detach) and returns void.
            rac_events_set_telemetry_sink(UnsafeMutableRawPointer(mgr.ptr))

            // Note: Public events are handled directly by app developers via C++ callbacks
            // No Swift EventPublisher layer needed

            isRegistered = true
            SDKLogger(category: "CppBridge.Events").debug("Registered C++ telemetry sink")
        }

        /// Detach the C++ telemetry sink.
        static func unregister() {
            guard isRegistered else { return }
            rac_events_set_telemetry_sink(nil)
            isRegistered = false
        }
    }
}

// MARK: - Telemetry Bridge

extension CppBridge {

    /// Telemetry bridge
    /// C++ handles JSON building, batching; Swift handles HTTP transport only
    public enum Telemetry {

        // Per AGENTS.md: NSLock is forbidden — use `OSAllocatedUnfairLock`.
        // The lock guards an opaque manager pointer wrapped in a Sendable shim;
        // `OpaquePointer` itself is not Sendable under Swift 6.
        private static let manager = OSAllocatedUnfairLock<ManagerHandle?>(initialState: nil)
        private static let activeEnvironment = OSAllocatedUnfairLock<SDKEnvironment?>(initialState: nil)

        /// Initialize telemetry manager
        static func initialize(environment: SDKEnvironment) {
            // Destroy existing if any
            let existing = manager.withLock { $0 }
            if let existing {
                rac_telemetry_manager_destroy(existing.ptr)
            }

            activeEnvironment.withLock { $0 = environment }

            let deviceId = CppBridge.Device.persistentId
            let deviceInfo = DeviceInfoFactory.current

            let createdPtr: OpaquePointer? = deviceId.withCString { did in
                SDKConstants.platform.withCString { plat in
                    SDKConstants.version.withCString { ver in
                        rac_telemetry_manager_create(Environment.toC(environment), did, plat, ver)
                    }
                }
            }

            let newManager: ManagerHandle? = createdPtr.map { ManagerHandle(ptr: $0) }
            manager.withLock { $0 = newManager }

            // Set device info
            deviceInfo.deviceModel.withCString { model in
                deviceInfo.osVersion.withCString { os in
                    rac_telemetry_manager_set_device_info(newManager?.ptr, model, os)
                }
            }

            // Register HTTP callback - Swift provides HTTP transport for C++
            let userData = Unmanaged.passUnretained(Telemetry.self as AnyObject).toOpaque()
            rac_telemetry_manager_set_http_callback(newManager?.ptr, telemetryHttpCallback, userData)
        }

        /// Shutdown telemetry manager
        static func shutdown() {
            activeEnvironment.withLock { $0 = nil }

            let mgr = manager.withLock { current -> ManagerHandle? in
                let snapshot = current
                current = nil
                return snapshot
            }

            if let mgr {
                rac_telemetry_manager_flush(mgr.ptr)
                rac_telemetry_manager_destroy(mgr.ptr)
            }
        }

        /// The live telemetry-manager handle, if initialized.
        ///
        /// Exposed so `CppBridge.Events.register()` can attach it to the C++
        /// router as the telemetry sink (`rac_events_set_telemetry_sink`).
        /// `fileprivate` because `ManagerHandle` is a private file-scoped type;
        /// `register()` lives in this same file.
        fileprivate static var handle: ManagerHandle? {
            manager.withLock { $0 }
        }

        /// Flush pending events
        public static func flush() {
            guard let mgr = manager.withLock({ $0 }) else { return }
            rac_telemetry_manager_flush(mgr.ptr)
        }

        static var environment: SDKEnvironment? {
            activeEnvironment.withLock { $0 }
        }
    }
}

/// HTTP callback for telemetry - Swift provides HTTP transport for C++ telemetry
private func telemetryHttpCallback(
    userData _: UnsafeMutableRawPointer?,
    endpoint: UnsafePointer<CChar>?,
    jsonBody: UnsafePointer<CChar>?,
    jsonLength _: Int,
    requiresAuth: rac_bool_t
) {
    guard let endpoint = endpoint, let jsonBody = jsonBody else { return }

    let path = String(cString: endpoint)
    let json = String(cString: jsonBody)
    let needsAuth = requiresAuth == RAC_TRUE

    Task {
        await performTelemetryHTTP(path: path, json: json, requiresAuth: needsAuth)
    }
}

private func performTelemetryHTTP(path: String, json: String, requiresAuth: Bool) async {
    let logger = SDKLogger(category: "CppBridge.Telemetry")
    let environment = CppBridge.Telemetry.environment

    if environment == .development && !CppBridge.DevConfig.hasUsableSupabaseConfig {
        logger.debug("Skipping telemetry/device registration: no usable config")
        return
    }

    let hasUsableConfiguration = await CppBridge.HTTP.hasUsableConfiguration
    guard hasUsableConfiguration else {
        logger.debug("Skipping telemetry/device registration: no usable config")
        return
    }

    // Check if HTTP is configured before attempting request
    let isConfigured = await CppBridge.HTTP.shared.isConfigured
    guard isConfigured else {
        logger.debug("Skipping telemetry/device registration: no usable config")
        return
    }

    do {
        _ = try await CppBridge.HTTP.shared.post(path, json: json, requiresAuth: requiresAuth)
        logger.debug("✅ Telemetry sent to \(path)")
    } catch {
        logger.error("❌ HTTP failed for telemetry to \(path): \(error)")
    }
}

// MARK: - Event Emission Helpers (for Swift code that needs to emit events to C++)

extension CppBridge.Events {
    // MARK: - SDK Lifecycle Events

    /// Emit SDK init started event via the canonical SDK event proto stream.
    public static func emitSDKInitStarted() {
        publishInitialization(stage: .started)
    }

    /// Emit SDK init completed event via the canonical SDK event proto stream.
    public static func emitSDKInitCompleted(durationMs: Double) {
        var properties: [String: String] = [:]
        properties["duration_ms"] = String(durationMs)
        publishInitialization(stage: .completed, properties: properties)
    }

    /// Emit SDK init failed event via the canonical SDK event proto stream.
    public static func emitSDKInitFailed(error: SDKException) {
        publishInitialization(stage: .failed, error: error.message)
    }

    /// Emit SDK models loaded event via the canonical SDK event proto stream.
    public static func emitSDKModelsLoaded(count: Int) {
        publishInitialization(stage: .servicesBootstrapped, properties: ["model_count": String(count)])
    }

    /// Emit SDK models loaded with model IDs for richer attribution.
    public static func emitSDKModelsLoaded(modelIds: [String]) {
        publishInitialization(
            stage: .servicesBootstrapped,
            properties: [
                "model_count": String(modelIds.count),
                "model_ids": modelIds.joined(separator: ",")
            ]
        )
    }

    private static func publishInitialization(
        stage: RAInitializationStage,
        error: String = "",
        properties: [String: String] = [:]
    ) {
        var initialization = RAInitializationEvent()
        initialization.stage = stage
        initialization.error = error
        initialization.version = SDKConstants.version

        var event = RASDKEvent()
        event.id = UUID().uuidString
        event.timestampMs = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
        event.severity = stage == .failed ? .error : .info
        event.category = .initialization
        event.component = .unspecified
        event.destination = .all
        event.source = "swift"
        event.properties = properties
        event.initialization = initialization

        _ = publishSDKEvent(event)
    }
}
