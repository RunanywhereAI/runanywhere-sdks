//
//  CppBridge+ModelLifecycle.swift
//  RunAnywhere SDK
//
//  Canonical model/component lifecycle proto-byte bridge.
//

import CRACommons
import Foundation
import SwiftProtobuf

private enum ModelLifecycleProtoABI {
    typealias Load = @convention(c) (
        rac_model_registry_handle_t?,
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t
    typealias Request = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t
    typealias Snapshot = @convention(c) (
        UInt32,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t
    typealias Reset = @convention(c) () -> Void

    static let load = NativeProtoABI.load("rac_model_lifecycle_load_proto", as: Load.self)
    static let unload = NativeProtoABI.load("rac_model_lifecycle_unload_proto", as: Request.self)
    static let currentModel = NativeProtoABI.load(
        "rac_model_lifecycle_current_model_proto",
        as: Request.self
    )
    static let componentSnapshot = NativeProtoABI.load(
        "rac_component_lifecycle_snapshot_proto",
        as: Snapshot.self
    )
    static let reset = NativeProtoABI.load("rac_model_lifecycle_reset", as: Reset.self)
}

extension CppBridge {
    public enum ModelLifecycle {
        public static func load(_ request: RAModelLoadRequest) async -> RAModelLoadResult {
            guard let load = ModelLifecycleProtoABI.load,
                  NativeProtoABI.canReceiveProtoBuffer,
                  let registry = await CppBridge.ModelRegistry.shared.getHandle() else {
                var result = RAModelLoadResult()
                result.success = false
                result.modelID = request.modelID
                result.category = request.category
                result.framework = request.framework
                result.errorMessage = NativeProtoABI.unavailableMessage
                return result
            }

            do {
                var outBuffer = rac_proto_buffer_t()
                defer { NativeProtoABI.free(&outBuffer) }
                let status = try NativeProtoABI.withSerializedBytes(request) { bytes, size in
                    load(registry, bytes, size, &outBuffer)
                }
                guard status == RAC_SUCCESS else {
                    var result = RAModelLoadResult()
                    result.success = false
                    result.modelID = request.modelID
                    result.category = request.category
                    result.framework = request.framework
                    result.errorMessage = "Model lifecycle load failed: \(status)"
                    return result
                }
                return try NativeProtoABI.decode(RAModelLoadResult.self, from: outBuffer)
            } catch {
                var result = RAModelLoadResult()
                result.success = false
                result.modelID = request.modelID
                result.category = request.category
                result.framework = request.framework
                result.errorMessage = String(describing: error)
                return result
            }
        }

        public static func unload(_ request: RAModelUnloadRequest) -> RAModelUnloadResult {
            do {
                return try invoke(
                    request,
                    symbol: ModelLifecycleProtoABI.unload,
                    responseType: RAModelUnloadResult.self
                )
            } catch {
                var result = RAModelUnloadResult()
                result.success = false
                result.errorMessage = String(describing: error)
                return result
            }
        }

        public static func currentModel(
            _ request: RACurrentModelRequest
        ) -> RACurrentModelResult {
            (try? invoke(
                request,
                symbol: ModelLifecycleProtoABI.currentModel,
                responseType: RACurrentModelResult.self
            )) ?? RACurrentModelResult()
        }

        public static func componentSnapshot(
            component: RASDKComponent
        ) -> RAComponentLifecycleSnapshot? {
            guard let componentSnapshot = ModelLifecycleProtoABI.componentSnapshot,
                  NativeProtoABI.canReceiveProtoBuffer else {
                return nil
            }

            var outBuffer = rac_proto_buffer_t()
            defer { NativeProtoABI.free(&outBuffer) }
            let status = componentSnapshot(UInt32(component.rawValue), &outBuffer)
            guard status == RAC_SUCCESS else {
                return nil
            }
            return try? NativeProtoABI.decode(RAComponentLifecycleSnapshot.self, from: outBuffer)
        }

        public static func reset() {
            ModelLifecycleProtoABI.reset?()
        }

        private static func invoke<Request: Message, Response: Message>(
            _ request: Request,
            symbol: ModelLifecycleProtoABI.Request?,
            responseType: Response.Type
        ) throws -> Response {
            guard let symbol, NativeProtoABI.canReceiveProtoBuffer else {
                throw SDKException.general(.notSupported, NativeProtoABI.unavailableMessage)
            }

            var outBuffer = rac_proto_buffer_t()
            defer { NativeProtoABI.free(&outBuffer) }
            let status = try NativeProtoABI.withSerializedBytes(request) { bytes, size in
                symbol(bytes, size, &outBuffer)
            }
            guard status == RAC_SUCCESS else {
                throw SDKException.general(.processingFailed, "Model lifecycle request failed: \(status)")
            }
            return try NativeProtoABI.decode(responseType, from: outBuffer)
        }
    }
}
