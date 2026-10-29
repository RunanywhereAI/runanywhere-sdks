//
//  CppBridge+Decision.swift
//  RunAnywhere SDK
//
//  Joint decision scoring bridge over the generated proto-byte ABI.
//
//  Mirrors CppBridge+Rerank: the component-handle verb
//  `rac_decision_component_decide_proto` is resolved lazily via dlsym so the
//  SDK still compiles against a prebuilt RACommons that predates the ABI-v13
//  decision export set. This bridge owns a component handle, loads the
//  lifecycle-resolved model into it, then scores.
//

import CRACommons
import Foundation
import SwiftProtobuf

private enum DecisionComponentABI {
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
    typealias DecideProto = @convention(c) (
        rac_handle_t?,
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t

    static let create = NativeProtoABI.load("rac_decision_component_create", as: Create.self)
    static let isLoaded = NativeProtoABI.load("rac_decision_component_is_loaded", as: IsLoaded.self)
    static let loadModel = NativeProtoABI.load("rac_decision_component_load_model", as: LoadModel.self)
    static let unload = NativeProtoABI.load("rac_decision_component_unload", as: Unload.self)
    static let destroy = NativeProtoABI.load("rac_decision_component_destroy", as: Destroy.self)
    static let decideName = "rac_decision_component_decide_proto"
    static let decide = NativeProtoABI.load(decideName, as: DecideProto.self)
}

/// Opaque component pointer wrapper so the raw `rac_handle_t` can cross the
/// `Task.detached` boundary under Swift 6 strict concurrency. The value is only
/// unwrapped for one synchronous C call.
private struct DecisionHandle: @unchecked Sendable {
    let rawValue: rac_handle_t
}

extension CppBridge {
    /// Joint decision scoring namespace. Wraps the `rac_decision_component_*`
    /// C ABI: create a component, load the lifecycle-resolved model into it,
    /// and score a `RADecisionRequest` into a `RADecisionResult`.
    public actor Decision {
        public static let shared = Decision()

        private var handle: rac_handle_t?
        private var loadedModelID: String?
        /// The path the currently-loaded model came from. Tracked with the id
        /// because the lifecycle can load a different checkpoint under the same
        /// id (the dev CLIs do exactly that), and the component would otherwise
        /// keep scoring with the stale weights.
        private var loadedModelPath: String?
        private let logger = SDKLogger(category: "CppBridge.Decision")

        private init() {}

        /// One-shot decision via the lifecycle-loaded decision model.
        public func decide(
            _ request: RADecisionRequest,
            loadedModel snapshot: RAComponentLifecycleSnapshot
        ) async throws -> RADecisionResult {
            let componentHandle = DecisionHandle(rawValue: try prepareHandle(from: snapshot))
            let decideProto = try NativeProtoABI.require(
                DecisionComponentABI.decide,
                named: DecisionComponentABI.decideName
            )
            return try await Task.detached(priority: .userInitiated) {
                try NativeProtoABI.invoke(
                    request,
                    on: componentHandle.rawValue,
                    symbol: { ctx, bytes, size, outResult in
                        decideProto(ctx, bytes, size, outResult)
                    },
                    symbolName: DecisionComponentABI.decideName,
                    responseType: RADecisionResult.self
                )
            }.value
        }

        /// Unload the current model, leaving the component reusable.
        public func unload() {
            guard let handle = handle, let unloadFn = DecisionComponentABI.unload else { return }
            _ = unloadFn(handle)
            loadedModelID = nil
            loadedModelPath = nil
            logger.info("Decision model unloaded")
        }

        /// Destroy the component and release its C resources.
        public func destroy() {
            if let handle = handle, let destroyFn = DecisionComponentABI.destroy {
                destroyFn(handle)
                logger.debug("Decision component destroyed")
            }
            handle = nil
            loadedModelID = nil
            loadedModelPath = nil
        }

        // MARK: - Handle preparation (mirrors Rerank.prepareHandle)

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
                    message: "Loaded decision model is missing a resolved path",
                    category: .component
                )
            }
            let componentHandle = try getHandle()
            if loadedModelID == modelID && loadedModelPath == modelPath {
                return componentHandle
            }
            let loadModel = try NativeProtoABI.require(
                DecisionComponentABI.loadModel,
                named: "rac_decision_component_load_model"
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
                    message: "Failed to load decision model: \(status)",
                    category: .component
                )
            }
            loadedModelID = modelID
            loadedModelPath = modelPath
            logger.info("Decision model loaded: \(modelID)")
            return componentHandle
        }

        private func getHandle() throws -> rac_handle_t {
            if let handle = handle {
                return handle
            }
            let createFn = try NativeProtoABI.require(
                DecisionComponentABI.create,
                named: "rac_decision_component_create"
            )
            var newHandle: rac_handle_t?
            let status = createFn(&newHandle)
            guard status == RAC_SUCCESS, let created = newHandle else {
                throw SDKException(
                    code: .notInitialized,
                    message: "Failed to create decision component: \(status)",
                    category: .component
                )
            }
            handle = created
            logger.debug("Decision component created")
            return created
        }
    }
}
