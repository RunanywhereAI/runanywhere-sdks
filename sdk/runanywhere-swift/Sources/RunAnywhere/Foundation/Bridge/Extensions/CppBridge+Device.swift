//
//  CppBridge+Device.swift
//  RunAnywhere SDK
//
//  Device registration bridge extension for C++ interop.
//  Implements callbacks for C++ device manager to access Swift platform APIs.
//

import CRACommons
import Foundation
import os

// MARK: - Device Bridge

extension CppBridge {

    /// Device registration bridge
    /// C++ handles all business logic; Swift provides platform callbacks
    public enum Device {

        // MARK: - Callback Storage (must persist for C++ to call)

        private static var callbacksRegistered = false

        /// Per AGENTS.md, NSLock is forbidden — `OSAllocatedUnfairLock` only.
        private static let deviceInfoStrings =
            OSAllocatedUnfairLock<DeviceCStringStore>(initialState: DeviceCStringStore())
        private static let httpResponseStrings =
            OSAllocatedUnfairLock<DeviceCStringStore>(initialState: DeviceCStringStore())

        // MARK: - Persistent Device ID Cache

        /// In-process cache of the persistent device id resolved by commons.
        /// Commons also caches internally — this Swift cache avoids paying
        /// the C ABI round-trip on hot paths (telemetry, auth, device-info).
        /// Per AGENTS.md, NSLock is forbidden — `OSAllocatedUnfairLock` only.
        private static let cachedPersistentId =
            OSAllocatedUnfairLock<String?>(initialState: nil)

        /// Persistent device identifier (Keychain-backed, survives reinstalls).
        ///
        /// Walks the canonical chain inside commons:
        ///   1. secure_get("device_id")
        ///   2. get_vendor_id callback (UIDevice.identifierForVendor on iOS)
        ///   3. freshly synthesized RFC-4122 v4 UUID (then persisted)
        ///
        /// On the rare resolver failure (e.g. before the platform adapter is
        /// registered) we synthesize a one-shot UUID locally so callers always
        /// receive a stable, non-empty string for the SDK lifetime.
        public static var persistentId: String {
            if let cached = cachedPersistentId.withLock({ $0 }) {
                return cached
            }

            let resolved = resolvePersistentId()

            return cachedPersistentId.withLock { current in
                if let existing = current { return existing }
                current = resolved
                return resolved
            }
        }

        // swiftlint:disable:next no_apple_logger
        private static let fallbackLogger = Logger(subsystem: "com.runanywhere", category: "CppBridge.Device")

        private static func resolvePersistentId() -> String {
            let bufferSize = Int(RAC_DEVICE_ID_BUFFER_MIN_SIZE)
            var buffer = [CChar](repeating: 0, count: bufferSize)
            let result = buffer.withUnsafeMutableBufferPointer { ptr -> rac_result_t in
                guard let base = ptr.baseAddress else { return RAC_ERROR_NULL_POINTER }
                return rac_device_get_or_create_persistent_id(base, bufferSize)
            }

            if result == RAC_SUCCESS {
                return String(cString: buffer)
            }

            // Fallback: commons resolver unavailable (e.g. platform adapter
            // not yet registered). Synthesize a UUID so callers never see an
            // empty string. This is non-persistent for this run only.
            // Use os.Logger directly — SDKLogger would recurse via DeviceInfo.current.
            fallbackLogger.warning("rac_device_get_or_create_persistent_id failed (result=\(result)); using transient UUID")
            return UUID().uuidString
        }

        // MARK: - Public API

        // Register callbacks with C++ device manager.
        // Must be called during SDK initialization.
        // swiftlint:disable:next function_body_length
        public static func register() {
            guard !callbacksRegistered else { return }

            var callbacks = rac_device_callbacks_t()

            // Get device info callback - populates all fields needed by backend
            callbacks.get_device_info = { outInfo, _ in
                guard let outInfo = outInfo else { return }

                let deviceInfo = DeviceInfo.current
                let deviceId = CppBridge.Device.persistentId

                // Commons reads these `const char*` fields after this callback
                // returns, so back them with strdup'd storage that outlives the
                // call. The previous fill is freed before this one is staged.
                CppBridge.Device.deviceInfoStrings.withLock { store in
                    store.reset()

                    // Required fields (backend schema)
                    outInfo.pointee.device_id = store.dup(deviceId)
                    outInfo.pointee.device_model = store.dup(deviceInfo.deviceModel)
                    outInfo.pointee.device_name = store.dup(deviceInfo.deviceName)
                    outInfo.pointee.platform = store.dup(deviceInfo.platform)
                    outInfo.pointee.os_version = store.dup(deviceInfo.osVersion)
                    outInfo.pointee.form_factor = store.dup(deviceInfo.formFactor)
                    outInfo.pointee.architecture = store.dup(deviceInfo.architecture)
                    outInfo.pointee.chip_name = store.dup(deviceInfo.chipName)
                    outInfo.pointee.gpu_family = store.dup(deviceInfo.gpuFamily)
                    if let batteryState = deviceInfo.batteryState {
                        outInfo.pointee.battery_state = store.dup(batteryState)
                    }
                    outInfo.pointee.device_fingerprint = store.dup(deviceId)
                }

                outInfo.pointee.total_memory = Int64(deviceInfo.totalMemory)
                outInfo.pointee.available_memory = Int64(deviceInfo.availableMemory)
                outInfo.pointee.has_neural_engine = deviceInfo.hasNeuralEngine ? RAC_TRUE : RAC_FALSE
                outInfo.pointee.neural_engine_cores = Int32(deviceInfo.neuralEngineCores)
                outInfo.pointee.battery_level = deviceInfo.batteryLevel ?? -1.0
                outInfo.pointee.is_low_power_mode = deviceInfo.isLowPowerMode ? RAC_TRUE : RAC_FALSE
                outInfo.pointee.core_count = Int32(deviceInfo.coreCount)
                outInfo.pointee.performance_cores = Int32(deviceInfo.performanceCores)
                outInfo.pointee.efficiency_cores = Int32(deviceInfo.efficiencyCores)
            }

            // Get device ID callback
            callbacks.get_device_id = { _ in
                let deviceId = CppBridge.Device.persistentId
                return (deviceId as NSString).utf8String
            }

            // Check if registered callback
            // Note: Cannot capture context in C function pointer, so use literal key
            callbacks.is_registered = { _ in
                return UserDefaults.standard.bool(forKey: "com.runanywhere.sdk.deviceRegistered") ? RAC_TRUE : RAC_FALSE
            }

            // Set registered callback
            // Note: Cannot capture context in C function pointer, so use literal key
            callbacks.set_registered = { registered, _ in
                if registered == RAC_TRUE {
                    UserDefaults.standard.set(true, forKey: "com.runanywhere.sdk.deviceRegistered")
                } else {
                    UserDefaults.standard.removeObject(forKey: "com.runanywhere.sdk.deviceRegistered")
                }
            }

            // HTTP POST callback
            callbacks.http_post = { endpoint, jsonBody, requiresAuth, outResponse, _ -> rac_result_t in
                guard let endpoint = endpoint, let jsonBody = jsonBody, let outResponse = outResponse else {
                    return RAC_ERROR_INVALID_ARGUMENT
                }

                let endpointStr = String(cString: endpoint)
                let jsonStr = String(cString: jsonBody)
                let needsAuth = requiresAuth == RAC_TRUE

                // Bridge the async HTTP call back to this synchronous C callback.
                // `Task.detached` keeps the work off the caller's actor: commons
                // can invoke http_post from the MainActor during init, and a
                // plain `Task {}` could be scheduled onto that same blocked
                // executor, deadlocking against `semaphore.wait()`. The bounded
                // wait is a backstop against any residual hang.
                let semaphore = DispatchSemaphore(value: 0)
                let resultBox = OSAllocatedUnfairLock<rac_result_t>(initialState: RAC_ERROR_NETWORK_ERROR)

                Task.detached {
                    var status: rac_result_t = RAC_ERROR_NETWORK_ERROR
                    defer {
                        resultBox.withLock { $0 = status }
                        semaphore.signal()
                    }
                    do {
                        guard let jsonData = jsonStr.data(using: .utf8) else {
                            CppBridge.Device.writeHTTPResponse(
                                outResponse,
                                result: RAC_ERROR_INVALID_ARGUMENT,
                                statusCode: 0,
                                body: nil,
                                error: "Invalid JSON data"
                            )
                            status = RAC_ERROR_INVALID_ARGUMENT
                            return
                        }

                        let responseData = try await CppBridge.HTTP.shared.postRaw(
                            endpointStr,
                            jsonData,
                            requiresAuth: needsAuth
                        )

                        CppBridge.Device.writeHTTPResponse(
                            outResponse,
                            result: RAC_SUCCESS,
                            statusCode: 200,
                            body: String(data: responseData, encoding: .utf8),
                            error: nil
                        )
                        status = RAC_SUCCESS
                    } catch {
                        CppBridge.Device.writeHTTPResponse(
                            outResponse,
                            result: RAC_ERROR_NETWORK_ERROR,
                            statusCode: 0,
                            body: nil,
                            error: error.localizedDescription
                        )
                        status = RAC_ERROR_NETWORK_ERROR
                    }
                }

                guard semaphore.wait(timeout: .now() + 30) == .success else {
                    CppBridge.Device.writeHTTPResponse(
                        outResponse,
                        result: RAC_ERROR_TIMEOUT,
                        statusCode: 0,
                        body: nil,
                        error: "Device registration HTTP request timed out"
                    )
                    return RAC_ERROR_TIMEOUT
                }
                return resultBox.withLock { $0 }
            }

            callbacks.user_data = nil

            let setResult = rac_device_manager_set_callbacks(&callbacks)
            if setResult == RAC_SUCCESS {
                callbacksRegistered = true
                SDKLogger(category: "CppBridge.Device").debug("Device manager callbacks registered")
            } else {
                SDKLogger(category: "CppBridge.Device").error("Failed to register device manager callbacks: \(setResult)")
            }
        }

        /// Populate `rac_device_http_response_t`. Commons reads `response_body`
        /// / `error_message` after the http_post callback returns and does not
        /// take ownership, so the strings are strdup'd into a store freed on the
        /// next response (avoiding both the autorelease UAF and an unbounded
        /// leak).
        private static func writeHTTPResponse(
            _ outResponse: UnsafeMutablePointer<rac_device_http_response_t>,
            result: rac_result_t,
            statusCode: Int32,
            body: String?,
            error: String?
        ) {
            httpResponseStrings.withLock { store in
                store.reset()
                outResponse.pointee.result = result
                outResponse.pointee.status_code = statusCode
                outResponse.pointee.response_body = body.flatMap { store.dup($0) }
                outResponse.pointee.error_message = error.flatMap { store.dup($0) }
            }
        }

        /// Register device with backend if not already registered
        /// All business logic is in C++ - this is just a thin wrapper
        public static func registerIfNeeded(environment: SDKEnvironment) async throws {
            guard callbacksRegistered else {
                throw SDKException(code: .notInitialized, message: "Device manager callbacks not registered", category: .internal)
            }

            if environment == .development && !CppBridge.DevConfig.hasUsableDevelopmentRegistrationConfig {
                SDKLogger(category: "CppBridge.Device")
                    .debug("Skipping telemetry/device registration: no usable config")
                return
            }

            let hasUsableHTTPConfiguration = await CppBridge.HTTP.hasUsableConfiguration
            if environment != .development && !hasUsableHTTPConfiguration {
                SDKLogger(category: "CppBridge.Device")
                    .debug("Skipping telemetry/device registration: no usable config")
                return
            }

            // Get build token for development mode
            let buildTokenString = environment == .development ? CppBridge.DevConfig.buildToken : nil

            let result: rac_result_t
            if let token = buildTokenString {
                result = token.withCString { tokenPtr in
                    rac_device_manager_register_if_needed(Environment.toC(environment), tokenPtr)
                }
            } else {
                result = rac_device_manager_register_if_needed(Environment.toC(environment), nil)
            }

            // RAC_SUCCESS means registered successfully or already registered
            if result != RAC_SUCCESS {
                throw SDKException(code: .serviceNotAvailable, message: "Device registration failed: \(result)", category: .network)
            }
        }

        /// Check if device is registered
        public static var isRegistered: Bool {
            return rac_device_manager_is_registered() == RAC_TRUE
        }

        /// Clear registration status
        public static func clearRegistration() {
            rac_device_manager_clear_registration()
        }

        /// Get the device ID
        public static var deviceId: String? {
            guard let ptr = rac_device_manager_get_device_id() else { return nil }
            return String(cString: ptr)
        }

        // `buildRegistrationJSON` DELETED. Use registerIfNeeded()
        // — all registration logic now lives in C++ via the rac_device_manager
        // API; Swift no longer needs to hand-build the JSON request.
    }
}

/// Owns `strdup`'d C-string backing for `const char*` fields that commons
/// reads after a device callback returns (device-info struct, http response).
/// `(NSString).utf8String` is only valid until the autorelease pool drains;
/// these copies survive the callback and are freed when the next fill calls
/// `reset()`, bounding the lifetime to one outstanding generation.
private final class DeviceCStringStore {
    private var buffers: [UnsafeMutablePointer<CChar>] = []

    /// Duplicate `value` into long-lived storage and return a pointer valid
    /// until the next `reset()`.
    func dup(_ value: String) -> UnsafePointer<CChar>? {
        guard let copy = strdup(value) else { return nil }
        buffers.append(copy)
        return UnsafePointer(copy)
    }

    func reset() {
        buffers.forEach { free($0) }
        buffers.removeAll(keepingCapacity: true)
    }
}
