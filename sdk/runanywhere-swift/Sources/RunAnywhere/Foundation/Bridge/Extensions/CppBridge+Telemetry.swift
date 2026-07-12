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

/// Owns every unstructured telemetry HTTP task for exactly one SDK lifetime.
///
/// The C callback is synchronous, while HTTP delivery is asynchronous. Without
/// an explicit registry, a callback task can survive reset and read the next
/// lifetime's credentials from `HTTPClientAdapter`. Admission and the task map
/// are protected by one unfair lock; normal shutdown closes admission and
/// awaits the snapshot, while synchronous partial-init rollback cancels and
/// waits for the same group before another lifetime can begin.
final class TelemetryHTTPTaskRegistry: @unchecked Sendable {
    private struct State {
        var generation: UInt64 = 0
        var acceptsTasks = false
        var nextTaskID: UInt64 = 0
        var tasks: [UInt64: Task<Void, Never>] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let pendingTasks = DispatchGroup()

    /// Start a fresh admission generation after fail-closed retirement of any
    /// inconsistent prior state.
    @discardableResult
    func beginLifetime() -> UInt64 {
        cancelAndWait()
        return state.withLock { current in
            current.generation &+= 1
            current.acceptsTasks = true
            return current.generation
        }
    }

    /// Admit one callback task into the current lifetime. Returns false after
    /// shutdown has closed admission, so late native callbacks are discarded.
    @discardableResult
    func submit(_ operation: @escaping @Sendable () async -> Void) -> Bool {
        state.withLock { current in
            guard current.acceptsTasks else { return false }

            current.nextTaskID &+= 1
            let taskID = current.nextTaskID
            let generation = current.generation
            pendingTasks.enter()
            current.tasks[taskID] = Task { [self] in
                defer { finish(taskID: taskID, generation: generation) }
                guard !Task.isCancelled else { return }
                await operation()
            }
            return true
        }
    }

    /// Close callback admission and await every task already handed off by C++.
    func drain() async {
        let tasks = closeAdmission(cancel: false)
        for task in tasks {
            await task.value
        }
    }

    /// Fail-closed synchronous retirement for Phase-1 rollback. No HTTP adapter
    /// is configured before Phase 2, so cancellation completes without waiting
    /// on a configured network request and prevents work crossing into a retry.
    func cancelAndWait() {
        _ = closeAdmission(cancel: true)
        pendingTasks.wait()
    }

    var pendingTaskCount: Int {
        state.withLock { $0.tasks.count }
    }

    private func closeAdmission(cancel: Bool) -> [Task<Void, Never>] {
        let tasks = state.withLock { current -> [Task<Void, Never>] in
            current.acceptsTasks = false
            return Array(current.tasks.values)
        }
        if cancel {
            tasks.forEach { $0.cancel() }
        }
        return tasks
    }

    private func finish(taskID: UInt64, generation: UInt64) {
        state.withLock { current in
            if current.generation == generation {
                current.tasks.removeValue(forKey: taskID)
            }
        }
        pendingTasks.leave()
    }
}

private let telemetryHTTPTasks = TelemetryHTTPTaskRegistry()

// MARK: - Events Bridge

extension CppBridge {

    /// Analytics events bridge
    /// C++ handles all event logic - Swift just handles HTTP transport
    public enum Events {

        private static let registration = OSAllocatedUnfairLock(initialState: false)

        /// Register the C++ telemetry sink.
        ///
        /// The C++ destination-bitmask router (`rac::events::route`) now drives
        /// telemetry internally: it calls `rac_telemetry_manager_track_proto`
        /// for every event whose destination carries the TELEMETRY bit. Swift
        /// only has to attach the telemetry manager once as the sink — there is
        /// no per-event analytics callback to translate anymore.
        static func register() {
            registration.withLock { isRegistered in
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
        }

        /// Detach the C++ telemetry sink.
        static func unregister() {
            registration.withLock { isRegistered in
                guard isRegistered else { return }
                rac_events_set_telemetry_sink(nil)
                isRegistered = false
            }
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
        static func initialize(environment: SDKEnvironment, deviceId: String) {
            // Fail closed if an inconsistent caller skipped shutdown. Existing
            // callback tasks must finish before a new credential lifetime opens.
            telemetryHTTPTasks.cancelAndWait()
            let existing = manager.withLock { current -> ManagerHandle? in
                let snapshot = current
                current = nil
                return snapshot
            }
            if let existing {
                rac_telemetry_manager_destroy(existing.ptr)
            }

            telemetryHTTPTasks.beginLifetime()
            activeEnvironment.withLock { $0 = environment }

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

        /// Shutdown telemetry manager and drain every accepted HTTP callback.
        static func shutdown() async {
            let mgr = manager.withLock { current -> ManagerHandle? in
                let snapshot = current
                current = nil
                return snapshot
            }

            if let mgr {
                rac_telemetry_manager_flush(mgr.ptr)
                rac_telemetry_manager_destroy(mgr.ptr)
            }

            // `flush` invokes the C callback synchronously, so by this point all
            // terminal batches are admitted. Close admission before awaiting to
            // prevent a late callback from escaping this SDK lifetime.
            await telemetryHTTPTasks.drain()
            activeEnvironment.withLock { $0 = nil }
        }

        /// Synchronous fail-closed teardown used only while Phase 1 is rolling
        /// back. Phase 2 has not configured HTTP yet, so pending callback tasks
        /// are canceled and joined instead of being allowed into a later retry.
        static func rollbackInitialization() {
            let mgr = manager.withLock { current -> ManagerHandle? in
                let snapshot = current
                current = nil
                return snapshot
            }

            if let mgr {
                rac_telemetry_manager_flush(mgr.ptr)
                rac_telemetry_manager_destroy(mgr.ptr)
            }

            telemetryHTTPTasks.cancelAndWait()
            activeEnvironment.withLock { $0 = nil }
        }

        /// The live telemetry-manager handle, if initialized.
        ///
        /// Exposed so `CppBridge.Events.register()` can attach it to the C++
        /// router as the telemetry sink (`rac_events_set_telemetry_sink`).
        /// `fileprivate` because `ManagerHandle` is a private file-scoped type;
        /// `register()` lives in this same file.
        fileprivate static var handle: ManagerHandle? { // swiftlint:disable:this strict_fileprivate
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

    telemetryHTTPTasks.submit {
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
        logger.warning("Telemetry delivery failed; request details omitted")
    }
}

// MARK: - Event Emission Helpers (for Swift code that needs to emit events to C++)

extension CppBridge.Events {
    // MARK: - SDK Lifecycle Events

    // SDK init STARTED/COMPLETED/FAILED are published once by commons
    // (rac_sdk_init_phase1_proto) — Swift no longer hand-emits them.

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
