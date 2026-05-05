//
//  CppBridge+Hardware.swift
//  RunAnywhere SDK
//
//  Canonical hardware profile proto-byte bridge.
//

import CRACommons
import Foundation

private enum HardwareProtoABI {
    typealias GetBytes = @convention(c) (
        UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
        UnsafeMutablePointer<Int>?
    ) -> rac_result_t
    typealias FreeBytes = @convention(c) (UnsafeMutablePointer<UInt8>?) -> Void
    typealias SetPreference = @convention(c) (CInt) -> rac_result_t

    static let profile = NativeProtoABI.load(
        "rac_hardware_profile_get",
        as: GetBytes.self
    )
    static let accelerators = NativeProtoABI.load(
        "rac_hardware_get_accelerators",
        as: GetBytes.self
    )
    static let free = NativeProtoABI.load(
        "rac_hardware_profile_free",
        as: FreeBytes.self
    )
    static let setPreference = NativeProtoABI.load(
        "rac_hardware_set_accelerator_preference",
        as: SetPreference.self
    )
}

extension CppBridge {
    public enum Hardware {
        public static func getProfile() throws -> RAHardwareProfileResult {
            try invokeBytes(
                HardwareProtoABI.profile,
                symbolName: "rac_hardware_profile_get"
            )
        }

        public static func getAccelerators() throws -> [RAAcceleratorInfo] {
            let result: RAHardwareProfileResult = try invokeBytes(
                HardwareProtoABI.accelerators,
                symbolName: "rac_hardware_get_accelerators"
            )
            return result.accelerators
        }

        public static func setAcceleratorPreference(_ preference: RAAccelerationPreference) throws {
            guard let setPreference = HardwareProtoABI.setPreference else {
                throw SDKException.general(
                    .notSupported,
                    NativeProtoABI.missingSymbolMessage("rac_hardware_set_accelerator_preference")
                )
            }

            let status = setPreference(CInt(preference.rawValue))
            guard status == RAC_SUCCESS else {
                throw SDKException.general(
                    .processingFailed,
                    "Failed to set accelerator preference: \(status)"
                )
            }
        }

        private static func invokeBytes(
            _ symbol: HardwareProtoABI.GetBytes?,
            symbolName: String
        ) throws -> RAHardwareProfileResult {
            guard let symbol else {
                throw SDKException.general(
                    .notSupported,
                    NativeProtoABI.missingSymbolMessage(symbolName)
                )
            }
            guard let free = HardwareProtoABI.free else {
                throw SDKException.general(
                    .notSupported,
                    NativeProtoABI.missingSymbolMessage("rac_hardware_profile_free")
                )
            }

            var bytesPtr: UnsafeMutablePointer<UInt8>?
            var byteCount = 0
            let status = symbol(&bytesPtr, &byteCount)
            guard status == RAC_SUCCESS, let bytesPtr else {
                throw SDKException.general(
                    .processingFailed,
                    "Hardware proto request failed: \(status)"
                )
            }
            defer { free(bytesPtr) }

            return try RAHardwareProfileResult(
                serializedBytes: Data(bytes: bytesPtr, count: byteCount)
            )
        }
    }
}
