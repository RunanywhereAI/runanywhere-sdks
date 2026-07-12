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

        private static let callbacksRegistered = OSAllocatedUnfairLock(initialState: false)

        /// Per AGENTS.md, NSLock is forbidden — `OSAllocatedUnfairLock` only.
        private static let deviceInfoStrings =
            OSAllocatedUnfairLock<DeviceCStringStore>(initialState: DeviceCStringStore())
        private static let deviceIdString =
            OSAllocatedUnfairLock<DeviceCStringStore>(initialState: DeviceCStringStore())
        private static let httpResponseStrings =
            OSAllocatedUnfairLock<DeviceCStringStore>(initialState: DeviceCStringStore())

        // MARK: - Persistent Device ID Cache

        /// Last identity validated against durable storage. Synchronous C
        /// callbacks borrow this value after Phase 1 resolves it.
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
        /// Resolution fails closed: identities are cached only after commons
        /// confirms the value was durably persisted.
        public static var persistentId: String {
            get throws {
                let resolved = try resolvePersistentId()
                cachedPersistentId.withLock { $0 = resolved }
                return resolved
            }
        }

        /// The already-validated identity used by synchronous C callbacks.
        static var resolvedPersistentId: String? {
            cachedPersistentId.withLock { $0 }
        }

        private static func resolvePersistentId() throws -> String {
            let bufferSize = Int(RAC_DEVICE_ID_BUFFER_MIN_SIZE)
            var buffer = [CChar](repeating: 0, count: bufferSize)
            let result = buffer.withUnsafeMutableBufferPointer { ptr -> rac_result_t in
                guard let base = ptr.baseAddress else { return RAC_ERROR_NULL_POINTER }
                return rac_device_get_or_create_persistent_id(base, bufferSize)
            }
            try SDKException.throwIfError(result)

            let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            guard let value = String(bytes: bytes, encoding: .utf8), !value.isEmpty else {
                throw SDKException(
                    code: .processingFailed,
                    message: "Persistent device ID resolver returned an empty value",
                    category: .internal
                )
            }
            return value
        }

        // MARK: - Public API

        // Register callbacks with C++ device manager.
        // Must be called during SDK initialization.
        // swiftlint:disable:next function_body_length
        public static func register() throws {
            let shouldRegister = callbacksRegistered.withLock { registered in
                guard !registered else { return false }
                registered = true
                return true
            }
            guard shouldRegister else { return }

            var callbacks = rac_device_callbacks_t()

            // Get device info callback - populates all fields needed by backend
            callbacks.get_device_info = { outInfo, _ in
                guard let outInfo = outInfo,
                      let deviceId = CppBridge.Device.resolvedPersistentId else { return }

                let deviceInfo = DeviceInfoFactory.current

                // Commons reads these `const char*` fields after this callback
                // returns, so back them with strdup'd storage that outlives the
                // call. The previous fill is freed before this one is staged.
                CppBridge.Device.deviceInfoStrings.withLockUnchecked { store in
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
                    if deviceInfo.hasBatteryState {
                        outInfo.pointee.battery_state = store.dup(deviceInfo.batteryState)
                    }
                    outInfo.pointee.device_fingerprint = store.dup(deviceId)
                }

                outInfo.pointee.total_memory = deviceInfo.totalMemory
                outInfo.pointee.available_memory = deviceInfo.availableMemory
                outInfo.pointee.has_neural_engine = deviceInfo.hasNeuralEngine_p ? RAC_TRUE : RAC_FALSE
                outInfo.pointee.neural_engine_cores = deviceInfo.neuralEngineCores
                outInfo.pointee.battery_level = deviceInfo.hasBatteryLevel ? Double(deviceInfo.batteryLevel) : -1.0
                outInfo.pointee.is_low_power_mode = deviceInfo.isLowPowerMode ? RAC_TRUE : RAC_FALSE
                outInfo.pointee.core_count = deviceInfo.coreCount
                outInfo.pointee.performance_cores = deviceInfo.performanceCores
                outInfo.pointee.efficiency_cores = deviceInfo.efficiencyCores
            }

            // Get device ID callback
            callbacks.get_device_id = { _ in
                guard let deviceId = CppBridge.Device.resolvedPersistentId else { return nil }
                return CppBridge.Device.deviceIdString.withLockUnchecked { store in
                    store.reset()
                    return store.dup(deviceId)
                }
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
                let resultBox = OSAllocatedUnfairLock<DeviceHTTPResult>(
                    initialState: .failure(
                        result: RAC_ERROR_NETWORK_ERROR,
                        message: "Device registration HTTP request failed"
                    )
                )

                Task.detached {
                    let payload: DeviceHTTPResult
                    do {
                        guard let jsonData = jsonStr.data(using: .utf8) else {
                            resultBox.withLock {
                                $0 = .failure(
                                    result: RAC_ERROR_INVALID_ARGUMENT,
                                    message: "Invalid JSON data"
                                )
                            }
                            semaphore.signal()
                            return
                        }

                        let responseData = try await CppBridge.HTTP.shared.postRaw(
                            endpointStr,
                            jsonData,
                            requiresAuth: needsAuth
                        )

                        payload = .success(
                            statusCode: 200,
                            body: String(data: responseData, encoding: .utf8)
                        )
                    } catch {
                        payload = .failure(
                            result: RAC_ERROR_NETWORK_ERROR,
                            message: error.localizedDescription
                        )
                    }
                    resultBox.withLock { $0 = payload }
                    semaphore.signal()
                }

                let payload: DeviceHTTPResult
                if semaphore.wait(timeout: .now() + 30) == .success {
                    payload = resultBox.withLock { $0 }
                } else {
                    payload = .failure(
                        result: RAC_ERROR_TIMEOUT,
                        message: "Device registration HTTP request timed out"
                    )
                }

                CppBridge.Device.writeHTTPResponse(outResponse, payload: payload)
                return payload.result
            }

            callbacks.user_data = nil

            let setResult = rac_device_manager_set_callbacks(&callbacks)
            if setResult == RAC_SUCCESS {
                SDKLogger(category: "CppBridge.Device").debug("Device manager callbacks registered")
            } else {
                callbacksRegistered.withLock { $0 = false }
                SDKLogger(category: "CppBridge.Device").error("Failed to register device manager callbacks: \(setResult)")
                try SDKException.throwIfError(setResult)
            }
        }

        /// Quiesce native callbacks and clear all process-local identity state.
        /// Keychain data and the device-registration flag remain durable.
        static func unregister() {
            rac_device_manager_clear_callbacks()
            callbacksRegistered.withLock { $0 = false }
            cachedPersistentId.withLock { $0 = nil }
            deviceInfoStrings.withLockUnchecked { $0.reset() }
            deviceIdString.withLockUnchecked { $0.reset() }
            httpResponseStrings.withLockUnchecked { $0.reset() }
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
            httpResponseStrings.withLockUnchecked { store in
                store.reset()
                outResponse.pointee.result = result
                outResponse.pointee.status_code = statusCode
                outResponse.pointee.response_body = body.flatMap { store.dup($0) }
                outResponse.pointee.error_message = error.flatMap { store.dup($0) }
            }
        }

        private static func writeHTTPResponse(
            _ outResponse: UnsafeMutablePointer<rac_device_http_response_t>,
            payload: DeviceHTTPResult
        ) {
            switch payload {
            case let .success(statusCode, body):
                writeHTTPResponse(
                    outResponse,
                    result: RAC_SUCCESS,
                    statusCode: statusCode,
                    body: body,
                    error: nil
                )
            case let .failure(result, message):
                writeHTTPResponse(
                    outResponse,
                    result: result,
                    statusCode: 0,
                    body: nil,
                    error: message
                )
            }
        }

        /// Check if device is registered
        public static var isRegistered: Bool {
            return rac_device_manager_is_registered() == RAC_TRUE
        }

        /// Get the device ID
        public static var deviceId: String? {
            guard let ptr = rac_device_manager_get_device_id() else { return nil }
            return String(cString: ptr)
        }
    }
}

/// Owns `strdup`'d C-string backing for `const char*` fields that commons
/// reads after a device callback returns (device-info struct, http response).
/// `(NSString).utf8String` is only valid until the autorelease pool drains;
/// these copies survive the callback and are freed when the next fill calls
/// `reset()`, bounding the lifetime to one outstanding generation.
/// The stores are private and every access is serialized by their enclosing
/// `OSAllocatedUnfairLock`; the pointers never escape except as borrowed C ABI
/// string storage with the documented generation lifetime.
private final class DeviceCStringStore: @unchecked Sendable {
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

private enum DeviceHTTPResult: Sendable {
    case success(statusCode: Int32, body: String?)
    case failure(result: rac_result_t, message: String)

    var result: rac_result_t {
        switch self {
        case .success:
            return RAC_SUCCESS
        case let .failure(result, _):
            return result
        }
    }
}
