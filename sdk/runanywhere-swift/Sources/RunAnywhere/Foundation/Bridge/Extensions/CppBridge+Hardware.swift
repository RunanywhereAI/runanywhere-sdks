//
//  CppBridge+Hardware.swift
//  RunAnywhere SDK
//
//  Canonical hardware profile proto-byte bridge.
//

import CRACommons

private enum HardwareProtoABI {
    typealias SetPreference = @convention(c) (CInt) -> rac_result_t

    static let profile = NativeProtoABI.load(
        "rac_hardware_profile_get",
        as: NativeProtoABI.GetBytes.self
    )
    static let accelerators = NativeProtoABI.load(
        "rac_hardware_get_accelerators",
        as: NativeProtoABI.GetBytes.self
    )
    static let free = NativeProtoABI.load(
        "rac_hardware_profile_free",
        as: NativeProtoABI.BytesFree.self
    )
    static let setPreference = NativeProtoABI.load(
        "rac_hardware_set_accelerator_preference",
        as: SetPreference.self
    )
}

extension CppBridge {
    public enum Hardware {
        public static func getProfile() throws -> RAHardwareProfileResult {
            try NativeProtoABI.getBytes(
                symbol: HardwareProtoABI.profile,
                symbolName: "rac_hardware_profile_get",
                freeBytes: HardwareProtoABI.free,
                freeBytesName: "rac_hardware_profile_free",
                responseType: RAHardwareProfileResult.self
            )
        }

        public static func getAccelerators() throws -> [RAAcceleratorInfo] {
            let result: RAHardwareProfileResult = try NativeProtoABI.getBytes(
                symbol: HardwareProtoABI.accelerators,
                symbolName: "rac_hardware_get_accelerators",
                freeBytes: HardwareProtoABI.free,
                freeBytesName: "rac_hardware_profile_free",
                responseType: RAHardwareProfileResult.self
            )
            return result.accelerators
        }

        public static func setAcceleratorPreference(_ preference: RAAccelerationPreference) throws {
            guard let setPreference = HardwareProtoABI.setPreference else {
                throw SDKException(
                    code: .notSupported,
                    message: NativeProtoABI.missingSymbolMessage("rac_hardware_set_accelerator_preference"),
                    category: .internal
                )
            }

            let status = setPreference(CInt(preference.rawValue))
            guard status == RAC_SUCCESS else {
                throw SDKException(
                    code: .processingFailed,
                    message: "Failed to set accelerator preference: \(status)",
                    category: .internal
                )
            }
        }
    }
}
