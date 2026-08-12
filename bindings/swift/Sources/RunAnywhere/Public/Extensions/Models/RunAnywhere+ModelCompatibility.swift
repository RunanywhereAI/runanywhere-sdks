//
//  RunAnywhere+ModelCompatibility.swift
//  RunAnywhere SDK
//
//  Thin Swift bridge over `rac_model_compatibility_check_proto`. Platforms
// supply available RAM / storage probes; commons owns can_run / can_fit.
//

import Foundation

public extension RunAnywhere.Models {

    /// Evaluate one registered model against the device's current available
    /// RAM and free storage. The verdict is owned by commons.
    ///
    /// - Throws: `SDKException` when the SDK is not ready or the native
    ///   compatibility ABI is unavailable / fails.
    func checkCompatibility(id: String) async throws -> RAModelCompatibilityResult {
        var request = RAModelCompatibilityRequest()
        request.modelID = id
        request.availableRamBytes = DeviceInfoFactory.current.availableMemoryBytes
        request.availableStorageBytes = CppBridge.FileManager.getStorageInfo().device_free
        return try await checkCompatibility(request)
    }

    /// Evaluate a caller-provided canonical compatibility request.
    func checkCompatibility(
        _ request: RAModelCompatibilityRequest
    ) async throws -> RAModelCompatibilityResult {
        guard RunAnywhere.isReady else {
            throw SDKException(
                code: .notInitialized,
                message: "SDK not initialized",
                category: .internal
            )
        }
        let result = try NativeProtoABI.invoke(
            request,
            symbol: NativeProtoABI.load(
                "rac_model_compatibility_check_proto",
                as: NativeProtoABI.ProtoRequest.self
            ),
            symbolName: "rac_model_compatibility_check_proto",
            responseType: RAModelCompatibilityResult.self
        )
        if result.hasError {
            throw SDKException(proto: result.error)
        }
        return result
    }
}
