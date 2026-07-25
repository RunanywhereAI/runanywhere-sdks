//
//  CppBridge+Rerank.swift
//  RunAnywhere SDK
//
//  Cross-encoder reranking bridge over the generated proto-byte ABI.
//
//  Unlike segmentation / diarization (which each publish a handle-free
//  `*_lifecycle_proto` verb), the revived rerank primitive only ships the
//  component-handle verb `rac_rerank_component_rerank_proto`, whose
//  `rac_lifecycle_acquire_service` is owner-scoped. This bridge therefore owns
//  a component handle and loads the lifecycle-resolved model into it before
//  scoring — mirroring the handle-prep half of
//  `CppBridge.Diarization.prepareStreamingHandle`. Every rerank symbol is
//  resolved lazily via `dlsym` so the SDK still compiles against a prebuilt
//  RACommons binary that predates the ABI-v8 rerank export set.
//

import CRACommons
import Foundation
import SwiftProtobuf

private enum RerankComponentABI {
    typealias Create = @convention(c) (UnsafeMutablePointer<rac_handle_t?>?) -> rac_result_t
    typealias IsLoaded = @convention(c) (rac_handle_t?) -> rac_bool_t
    typealias LoadModel = @convention(c) (
        rac_handle_t?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?
    ) -> rac_result_t
    typealias Unload = @convention(c) (rac_handle_t?) -> rac_result_t
    typealias Destroy = @convention(c) (rac_handle_t?) -> Void
    typealias RerankProto = @convention(c) (
        rac_handle_t?,
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t

    static let create = NativeProtoABI.load("rac_rerank_component_create", as: Create.self)
    static let isLoaded = NativeProtoABI.load("rac_rerank_component_is_loaded", as: IsLoaded.self)
    static let loadModel = NativeProtoABI.load("rac_rerank_component_load_model", as: LoadModel.self)
    static let unload = NativeProtoABI.load("rac_rerank_component_unload", as: Unload.self)
    static let destroy = NativeProtoABI.load("rac_rerank_component_destroy", as: Destroy.self)
    static let rerankName = "rac_rerank_component_rerank_proto"
    static let rerank = NativeProtoABI.load(rerankName, as: RerankProto.self)
}

/// Opaque component pointer wrapper so the raw `rac_handle_t` can cross the
/// `Task.detached` boundary under Swift 6 strict concurrency. The value is only
/// unwrapped for one synchronous C call.
private struct RerankHandle: @unchecked Sendable {
    let rawValue: rac_handle_t
}

extension CppBridge {
    /// Cross-encoder reranking namespace. Wraps the `rac_rerank_component_*` C
    /// ABI: create a component, load the lifecycle-resolved model into it, and
    /// score a `RARerankRequest` into a `RARerankResult`.
    public actor Rerank {
        public static let shared = Rerank()

        private var handle: rac_handle_t?
        private var loadedModelID: String?
        private let logger = SDKLogger(category: "CppBridge.Rerank")

        private init() {}

        /// One-shot rerank via the lifecycle-loaded cross-encoder model.
        ///
        /// Mirrors iOS parity for the other modalities: the loaded-model
        /// snapshot is resolved by `RunAnywhere.rerank`, its model is loaded
        /// into this component's handle (owner-scoped acquire), then the request
        /// is scored through `rac_rerank_component_rerank_proto`.
        public func rerank(
            _ request: RARerankRequest,
            loadedModel snapshot: RAComponentLifecycleSnapshot
        ) async throws -> RARerankResult {
            let componentHandle = RerankHandle(rawValue: try prepareHandle(from: snapshot))
            let rerankProto = try NativeProtoABI.require(
                RerankComponentABI.rerank,
                named: RerankComponentABI.rerankName
            )
            return try await Task.detached(priority: .userInitiated) {
                try NativeProtoABI.invoke(
                    request,
                    on: componentHandle.rawValue,
                    symbol: { ctx, bytes, size, outResult in
                        rerankProto(ctx, bytes, size, outResult)
                    },
                    symbolName: RerankComponentABI.rerankName,
                    responseType: RARerankResult.self
                )
            }.value
        }

        /// Unload the current model, leaving the component reusable.
        public func unload() {
            guard let handle = handle, let unloadFn = RerankComponentABI.unload else { return }
            _ = unloadFn(handle)
            loadedModelID = nil
            logger.info("Rerank model unloaded")
        }

        /// Destroy the component and release its C resources.
        public func destroy() {
            if let handle = handle, let destroyFn = RerankComponentABI.destroy {
                destroyFn(handle)
                logger.debug("Rerank component destroyed")
            }
            handle = nil
            loadedModelID = nil
        }

        // MARK: - Handle preparation (mirrors Diarization.prepareStreamingHandle)

        private func prepareHandle(
            from snapshot: RAComponentLifecycleSnapshot
        ) throws -> rac_handle_t {
            let modelID = snapshot.modelID.isEmpty ? snapshot.model.id : snapshot.modelID
            let modelName = snapshot.model.name.isEmpty ? modelID : snapshot.model.name
            let modelPath = snapshot.resolvedPath.isEmpty
                ? snapshot.model.localPath
                : snapshot.resolvedPath
            guard !modelID.isEmpty, !modelPath.isEmpty else {
                throw SDKException(
                    code: .modelLoadFailed,
                    message: "Loaded rerank model is missing a resolved path",
                    category: .component
                )
            }
            let componentHandle = try getHandle()
            if loadedModelID == modelID {
                return componentHandle
            }
            let loadModel = try NativeProtoABI.require(
                RerankComponentABI.loadModel,
                named: "rac_rerank_component_load_model"
            )
            let status = modelPath.withCString { pathPtr in
                modelID.withCString { idPtr in
                    modelName.withCString { namePtr in
                        loadModel(componentHandle, pathPtr, idPtr, namePtr)
                    }
                }
            }
            guard status == RAC_SUCCESS else {
                throw SDKException(
                    code: .modelLoadFailed,
                    message: "Failed to load rerank model: \(status)",
                    category: .component
                )
            }
            loadedModelID = modelID
            logger.info("Rerank model loaded: \(modelID)")
            return componentHandle
        }

        private func getHandle() throws -> rac_handle_t {
            if let handle = handle {
                return handle
            }
            let createFn = try NativeProtoABI.require(
                RerankComponentABI.create,
                named: "rac_rerank_component_create"
            )
            var newHandle: rac_handle_t?
            let status = createFn(&newHandle)
            guard status == RAC_SUCCESS, let created = newHandle else {
                throw SDKException(
                    code: .notInitialized,
                    message: "Failed to create rerank component: \(status)",
                    category: .component
                )
            }
            handle = created
            logger.debug("Rerank component created")
            return created
        }
    }
}
