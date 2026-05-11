//
//  CppBridge+VLM.swift
//  RunAnywhere SDK
//
//  VLM component bridge - manages C++ VLM component lifecycle.
//
//  Generic scaffolding (handle creation, isLoaded, unload, destroy)
//  lives in `CppBridge.ComponentActor`. VLM-specific surfaces kept here:
//   - 5-string `loadResolvedModel(...)` with an optional vision-projector
//     artifact (the path-only variant on the generic actor would lose
//     the projector slot)
//   - `loadModel(from:)` lifecycle adapters for `RAModelLoadResult` and
//     `RACurrentModelResult` (multi-artifact-aware)
//   - `cancel()`, `supportsStreaming`, and `state` introspection
//   - `currentModelPath` mirror used by the cross-actor lifecycle code.
//

import CRACommons
import Foundation

// MARK: - VLM Component Bridge

extension CppBridge {

    /// VLM component manager
    /// Provides thread-safe access to the C++ VLM component
    public actor VLM {

        /// Shared VLM component instance
        public static let shared = VLM()

        /// Generic scaffold (handle / isLoaded / destroy). VLM's
        /// vtable.loadModel uses the path-only overload of
        /// `rac_vlm_component_load_model` (NULL projector). The multi-
        /// artifact case goes through `loadResolvedModel(...)` below.
        private let inner = ComponentActor(vtable: .vlm)

        /// Mirror of the currently-loaded model id (also tracked on the
        /// inner actor via `markAssetLoaded`).
        private var loadedModelId: String?

        /// Mirror of the resolved primary-model path used by the
        /// `currentModelPath` accessor.
        private var loadedModelPath: String?

        private let logger = SDKLogger(category: "CppBridge.VLM")

        private init() {}

        // MARK: - Handle Management

        /// Get or create the VLM component handle
        public func getHandle() async throws -> rac_handle_t {
            try await inner.getHandle()
        }

        // MARK: - State

        /// Check if a model is loaded
        public var isLoaded: Bool {
            get async { await inner.isLoaded }
        }

        /// Get the currently loaded model ID
        public var currentModelId: String? { loadedModelId }

        /// Get the currently loaded model path
        public var currentModelPath: String? { loadedModelPath }

        // MARK: - Model Lifecycle

        func loadModel(from result: RAModelLoadResult, modelName: String? = nil) async throws {
            if loadedModelId == result.modelID, await inner.isLoaded {
                return
            }
            guard result.success else {
                throw SDKException(
                    code: .modelLoadFailed,
                    message: result.errorMessage.isEmpty ? "VLM lifecycle load failed" : result.errorMessage,
                    category: .component
                )
            }
            guard let primaryPath = result.resolvedPrimaryModelPath else {
                throw SDKException(
                    code: .modelLoadFailed,
                    message: "VLM lifecycle result did not include a primary model artifact",
                    category: .component
                )
            }

            let projectorPath = result.resolvedVisionProjectorPath
            if result.framework == .llamaCpp && projectorPath == nil {
                throw SDKException(
                    code: .modelLoadFailed,
                    message: "VLM lifecycle result did not include a vision projector artifact",
                    category: .component
                )
            }

            try await loadResolvedModel(
                primaryPath,
                visionProjectorPath: projectorPath,
                modelId: result.modelID,
                modelName: modelName ?? result.modelID
            )
        }

        func loadModel(from result: RACurrentModelResult) async throws {
            if loadedModelId == result.modelID, await inner.isLoaded {
                return
            }
            guard result.found else {
                throw SDKException(code: .modelLoadFailed, message: "No lifecycle-loaded VLM model found", category: .component)
            }
            guard let primaryPath = result.resolvedPrimaryModelPath else {
                throw SDKException(
                    code: .modelLoadFailed,
                    message: "Current VLM lifecycle result did not include a primary model artifact",
                    category: .component
                )
            }

            let projectorPath = result.resolvedVisionProjectorPath
            if result.framework == .llamaCpp && projectorPath == nil {
                throw SDKException(
                    code: .modelLoadFailed,
                    message: "Current VLM lifecycle result did not include a vision projector artifact",
                    category: .component
                )
            }

            try await loadResolvedModel(
                primaryPath,
                visionProjectorPath: projectorPath,
                modelId: result.modelID,
                modelName: result.hasModel && !result.model.name.isEmpty ? result.model.name : result.modelID
            )
        }

        /// Load a VLM model using artifacts already resolved by commons lifecycle.
        func loadResolvedModel(
            _ modelPath: String,
            visionProjectorPath: String?,
            modelId: String,
            modelName: String
        ) async throws {
            let handle = try await inner.getHandle()

            let result: rac_result_t
            if let visionProjectorPath = visionProjectorPath {
                result = modelPath.withCString { pathPtr in
                    visionProjectorPath.withCString { projectorPtr in
                        modelId.withCString { idPtr in
                            modelName.withCString { namePtr in
                                rac_vlm_component_load_model(handle, pathPtr, projectorPtr, idPtr, namePtr)
                            }
                        }
                    }
                }
            } else {
                result = modelPath.withCString { pathPtr in
                    modelId.withCString { idPtr in
                        modelName.withCString { namePtr in
                            rac_vlm_component_load_model(handle, pathPtr, nil, idPtr, namePtr)
                        }
                    }
                }
            }

            guard result == RAC_SUCCESS else {
                throw SDKException(code: .modelLoadFailed, message: "Failed to load VLM model: \(result)", category: .component)
            }

            loadedModelId = modelId
            loadedModelPath = modelPath
            await inner.markAssetLoaded(modelId)
            logger.info("VLM model loaded: \(modelId)")
        }

        /// Unload the current model
        public func unload() async {
            await inner.unload()
            loadedModelId = nil
            loadedModelPath = nil
        }

        /// Cancel ongoing generation
        public func cancel() async {
            guard let handle = await inner.existingHandle() else { return }
            _ = rac_vlm_component_cancel(handle)
        }

        /// Check if streaming is supported
        public var supportsStreaming: Bool {
            get async {
                guard let handle = await inner.existingHandle() else { return false }
                return rac_vlm_component_supports_streaming(handle) == RAC_TRUE
            }
        }

        /// Get lifecycle state
        public var state: rac_lifecycle_state_t {
            get async {
                guard let handle = await inner.existingHandle() else { return RAC_LIFECYCLE_STATE_IDLE }
                return rac_vlm_component_get_state(handle)
            }
        }

        // MARK: - Cleanup

        /// Destroy the component
        public func destroy() async {
            await inner.destroy()
            loadedModelId = nil
            loadedModelPath = nil
        }
    }
}
