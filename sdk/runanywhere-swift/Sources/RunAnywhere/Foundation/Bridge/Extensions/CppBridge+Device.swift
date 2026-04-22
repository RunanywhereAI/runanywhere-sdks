//
//  CppBridge+Device.swift
//  RunAnywhere SDK
//
//  Device registration bridge extension for C++ interop.
//  Implements callbacks for C++ device manager to access Swift platform APIs.
//

import CRACommons
import Foundation

// MARK: - Device Bridge

extension CppBridge {

    /// Device registration bridge
    /// C++ handles all business logic; Swift provides platform callbacks
    public enum Device {

        // MARK: - Callback Storage (must persist for C++ to call)

        private static var callbacksRegistered = false

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
                let deviceId = DeviceIdentity.persistentUUID

                #if targetEnvironment(simulator)
                let isSimulator = true
                #else
                let isSimulator = false
                #endif

                // Fill out the device info struct
                // Note: C strings are managed by Swift and remain valid during callback

                // Required fields (backend schema)
                outInfo.pointee.device_id = (deviceId as NSString).utf8String
                outInfo.pointee.device_model = (deviceInfo.deviceModel as NSString).utf8String
                outInfo.pointee.device_name = (deviceInfo.deviceName as NSString).utf8String
                outInfo.pointee.platform = (deviceInfo.platform as NSString).utf8String
                outInfo.pointee.os_version = (deviceInfo.osVersion as NSString).utf8String
                outInfo.pointee.form_factor = (deviceInfo.formFactor as NSString).utf8String
                outInfo.pointee.architecture = (deviceInfo.architecture as NSString).utf8String
                outInfo.pointee.chip_name = (deviceInfo.chipName as NSString).utf8String
                outInfo.pointee.total_memory = Int64(deviceInfo.totalMemory)
                outInfo.pointee.available_memory = Int64(deviceInfo.availableMemory)
                outInfo.pointee.has_neural_engine = deviceInfo.hasNeuralEngine ? RAC_TRUE : RAC_FALSE
                outInfo.pointee.neural_engine_cores = Int32(deviceInfo.neuralEngineCores)
                outInfo.pointee.gpu_family = (deviceInfo.gpuFamily as NSString).utf8String
                outInfo.pointee.battery_level = deviceInfo.batteryLevel ?? -1.0
                if let batteryState = deviceInfo.batteryState {
                    outInfo.pointee.battery_state = (batteryState as NSString).utf8String
                }
                outInfo.pointee.is_low_power_mode = deviceInfo.isLowPowerMode ? RAC_TRUE : RAC_FALSE
                outInfo.pointee.core_count = Int32(deviceInfo.coreCount)
                outInfo.pointee.performance_cores = Int32(deviceInfo.performanceCores)
                outInfo.pointee.efficiency_cores = Int32(deviceInfo.efficiencyCores)
                outInfo.pointee.device_fingerprint = (deviceId as NSString).utf8String

                // Legacy fields (backward compatibility)
                outInfo.pointee.device_type = (deviceInfo.deviceType as NSString).utf8String
                outInfo.pointee.os_name = ("iOS" as NSString).utf8String
                outInfo.pointee.processor_count = Int32(deviceInfo.coreCount)
                outInfo.pointee.is_simulator = isSimulator ? RAC_TRUE : RAC_FALSE
            }

            // Get device ID callback
            callbacks.get_device_id = { _ in
                let deviceId = DeviceIdentity.persistentUUID
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

                // Make synchronous HTTP call (we're already on a background thread from C++)
                let semaphore = DispatchSemaphore(value: 0)
                var result: rac_result_t = RAC_SUCCESS

                Task {
                    do {
                        guard let jsonData = jsonStr.data(using: .utf8) else {
                            outResponse.pointee.result = RAC_ERROR_INVALID_ARGUMENT
                            outResponse.pointee.status_code = 0
                            outResponse.pointee.error_message = ("Invalid JSON data" as NSString).utf8String
                            result = RAC_ERROR_INVALID_ARGUMENT
                            semaphore.signal()
                            return
                        }

                        // Use the HTTP bridge to make the request
                        let responseData = try await CppBridge.HTTP.shared.postRaw(
                            endpointStr,
                            jsonData,
                            requiresAuth: needsAuth
                        )

                        outResponse.pointee.result = RAC_SUCCESS
                        outResponse.pointee.status_code = 200
                        if let responseStr = String(data: responseData, encoding: .utf8) {
                            outResponse.pointee.response_body = (responseStr as NSString).utf8String
                        }
                        result = RAC_SUCCESS
                    } catch {
                        outResponse.pointee.result = RAC_ERROR_NETWORK_ERROR
                        outResponse.pointee.status_code = 0
                        outResponse.pointee.error_message = (error.localizedDescription as NSString).utf8String
                        result = RAC_ERROR_NETWORK_ERROR
                    }
                    semaphore.signal()
                }

                semaphore.wait()
                return result
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

        /// Register device with backend if not already registered
        /// All business logic is in C++ - this is just a thin wrapper
        public static func registerIfNeeded(environment: SDKEnvironment) async throws {
            guard callbacksRegistered else {
                throw SDKError.general(.notInitialized, "Device manager callbacks not registered")
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
                throw SDKError.network(.serviceNotAvailable, "Device registration failed: \(result)")
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

        // v3.0.0 (C2): `buildRegistrationJSON` DELETED. Use registerIfNeeded()
        // — all registration logic now lives in C++ via the rac_device_manager
        // API; Swift no longer needs to hand-build the JSON request.
    }
}
