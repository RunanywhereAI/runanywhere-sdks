//
//  CppBridge+ModelLifecycle.swift
//  RunAnywhere SDK
//
//  Canonical model/component lifecycle proto-byte bridge.
//

import CRACommons

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
                result.modelID = request.modelID
                result.category = request.category
                result.framework = request.framework
                result.error = RASDKError.make(
                    code: .modelLoadFailed,
                    message: NativeProtoABI.unavailableMessage,
                    category: .model
                )
                return result
            }

            do {
                var outBuffer = rac_proto_buffer_t()
                defer { NativeProtoABI.free(&outBuffer) }
                let status = try NativeProtoABI.withSerializedBytes(request) { bytes, size in
                    load(registry.rawValue, bytes, size, &outBuffer)
                }
                guard status == RAC_SUCCESS else {
                    var result = RAModelLoadResult()
                    result.modelID = request.modelID
                    result.category = request.category
                    result.framework = request.framework
                    result.error = RASDKError.make(
                        code: .modelLoadFailed,
                        message: "Model lifecycle load failed: \(status)",
                        category: .model
                    )
                    return result
                }
                return try NativeProtoABI.decode(RAModelLoadResult.self, from: outBuffer)
            } catch {
                var result = RAModelLoadResult()
                result.modelID = request.modelID
                result.category = request.category
                result.framework = request.framework
                result.error = RASDKError.make(
                    code: .modelLoadFailed,
                    message: String(describing: error),
                    category: .model
                )
                return result
            }
        }

        public static func unload(_ request: RAModelUnloadRequest) -> RAModelUnloadResult {
            do {
                return try NativeProtoABI.invoke(
                    request,
                    symbol: ModelLifecycleProtoABI.unload,
                    symbolName: "rac_model_lifecycle_unload_proto",
                    responseType: RAModelUnloadResult.self
                )
            } catch {
                var result = RAModelUnloadResult()
                result.error = RASDKError.make(
                    code: .internal,
                    message: String(describing: error),
                    category: .internal
                )
                return result
            }
        }

        public static func currentModel(
            _ request: RACurrentModelRequest
        ) -> RACurrentModelResult {
            (try? NativeProtoABI.invoke(
                request,
                symbol: ModelLifecycleProtoABI.currentModel,
                symbolName: "rac_model_lifecycle_current_model_proto",
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
    }
}
