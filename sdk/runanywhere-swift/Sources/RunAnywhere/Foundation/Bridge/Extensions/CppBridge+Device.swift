//
//  CppBridge+Device.swift
//  RunAnywhere SDK
//
//  Device registration bridge extension for C++ interop.
//

import CRACommons
import Foundation

// MARK: - Device Bridge

extension CppBridge {

    /// Device registration bridge
    /// C++ builds JSON; Swift provides device info + HTTP
    public enum Device {

        /// Build device registration JSON via C++
        public static func buildRegistrationJSON(buildToken: String? = nil) -> String? {
            let deviceInfo = DeviceInfo.current
            let deviceId = DeviceIdentity.persistentUUID
            let env = CppBridge.environment

            #if targetEnvironment(simulator)
            let isSimulator = true
            #else
            let isSimulator = false
            #endif

            var request = rac_device_registration_request_t()
            var cDeviceInfo = rac_device_registration_info_t()

            return deviceId.withCString { did in
                deviceInfo.deviceType.withCString { dtype in
                    deviceInfo.deviceModel.withCString { dmodel in
                        "iOS".withCString { osName in
                            deviceInfo.osVersion.withCString { osVer in
                                deviceInfo.platform.withCString { plat in
                                    SDKConstants.version.withCString { sdkVer in
                                        (buildToken ?? "").withCString { token in

                                            cDeviceInfo.device_id = did
                                            cDeviceInfo.device_type = dtype
                                            cDeviceInfo.device_model = dmodel
                                            cDeviceInfo.os_name = osName
                                            cDeviceInfo.os_version = osVer
                                            cDeviceInfo.platform = plat
                                            cDeviceInfo.total_memory_bytes = Int64(deviceInfo.totalMemory)
                                            cDeviceInfo.available_memory_bytes = Int64(deviceInfo.availableMemory)
                                            cDeviceInfo.processor_count = Int32(deviceInfo.coreCount)
                                            cDeviceInfo.is_simulator = isSimulator ? RAC_TRUE : RAC_FALSE

                                            request.device_info = cDeviceInfo
                                            request.sdk_version = sdkVer
                                            request.build_token = buildToken != nil ? token : nil
                                            request.last_seen_at_ms = Int64(Date().timeIntervalSince1970 * 1000)

                                            var jsonPtr: UnsafeMutablePointer<CChar>?
                                            var jsonLen: Int = 0

                                            let result = rac_device_registration_to_json(
                                                &request,
                                                Environment.toC(env),
                                                &jsonPtr,
                                                &jsonLen
                                            )

                                            if result == RAC_SUCCESS, let json = jsonPtr {
                                                let jsonString = String(cString: json)
                                                free(json)
                                                return jsonString
                                            }
                                            return nil
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        /// Register device with backend
        public static func register(buildToken: String? = nil) async throws {
            guard await CppBridge.HTTP.shared.isConfigured else {
                throw SDKError.network(.serviceNotAvailable, "HTTP not configured")
            }

            guard let json = buildRegistrationJSON(buildToken: buildToken) else {
                throw SDKError.general(.validationFailed, "Failed to build registration JSON")
            }

            let endpoint = Endpoints.deviceRegistration(for: CppBridge.environment)
            let requiresAuth = Environment.requiresAuth(CppBridge.environment)

            _ = try await CppBridge.HTTP.shared.post(endpoint, json: json, requiresAuth: requiresAuth)
        }
    }
}
