//
//  CppBridge+VLM.swift
//  RunAnywhere SDK
//
//  VLM component bridge - manages C++ VLM component lifecycle
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

        private var handle: rac_handle_t?
        private var loadedModelId: String?
        private var loadedModelPath: String?
        private var loadedVisionProjectorPath: String?
        private let logger = SDKLogger(category: "CppBridge.VLM")

        private init() {}

        // MARK: - Handle Management

        /// Get or create the VLM component handle
        public func getHandle() throws -> rac_handle_t {
            if let handle = handle {
                return handle
            }

            var newHandle: rac_handle_t?
            let result = rac_vlm_component_create(&newHandle)
            guard result == RAC_SUCCESS, let handle = newHandle else {
                throw SDKException.vlm(.notInitialized, "Failed to create VLM component: \(result)")
            }

            self.handle = handle
            logger.debug("VLM component created")
            return handle
        }

        // MARK: - State

        /// Check if a model is loaded
        public var isLoaded: Bool {
            guard let handle = handle else { return false }
            return rac_vlm_component_is_loaded(handle) == RAC_TRUE
        }

        /// Get the currently loaded model ID
        public var currentModelId: String? { loadedModelId }

        /// Get the currently loaded model path
        public var currentModelPath: String? { loadedModelPath }

        // MARK: - Model Lifecycle

        func loadModel(from result: RAModelLoadResult, modelName: String? = nil) throws {
            if loadedModelId == result.modelID, isLoaded {
                return
            }
            guard result.success else {
                throw SDKException.vlm(
                    .modelLoadFailed,
                    result.errorMessage.isEmpty ? "VLM lifecycle load failed" : result.errorMessage
                )
            }
            guard let primaryPath = result.resolvedPrimaryModelPath else {
                throw SDKException.vlm(
                    .modelLoadFailed,
                    "VLM lifecycle result did not include a primary model artifact"
                )
            }

            let projectorPath = result.resolvedVisionProjectorPath
            if result.framework == .llamaCpp && projectorPath == nil {
                throw SDKException.vlm(
                    .modelLoadFailed,
                    "VLM lifecycle result did not include a vision projector artifact"
                )
            }

            try loadResolvedModel(
                primaryPath,
                visionProjectorPath: projectorPath,
                modelId: result.modelID,
                modelName: modelName ?? result.modelID
            )
        }

        func loadModel(from result: RACurrentModelResult) throws {
            if loadedModelId == result.modelID, isLoaded {
                return
            }
            guard result.found else {
                throw SDKException.vlm(.modelLoadFailed, "No lifecycle-loaded VLM model found")
            }
            guard let primaryPath = result.resolvedPrimaryModelPath else {
                throw SDKException.vlm(
                    .modelLoadFailed,
                    "Current VLM lifecycle result did not include a primary model artifact"
                )
            }

            let projectorPath = result.resolvedVisionProjectorPath
            if result.framework == .llamaCpp && projectorPath == nil {
                throw SDKException.vlm(
                    .modelLoadFailed,
                    "Current VLM lifecycle result did not include a vision projector artifact"
                )
            }

            try loadResolvedModel(
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
        ) throws {
            let handle = try getHandle()

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
                throw SDKException.vlm(.modelLoadFailed, "Failed to load VLM model: \(result)")
            }

            loadedModelId = modelId
            loadedModelPath = modelPath
            loadedVisionProjectorPath = visionProjectorPath
            logger.info("VLM model loaded: \(modelId)")
        }

        /// Unload the current model
        public func unload() {
            guard let handle = handle else { return }
            rac_vlm_component_cleanup(handle)
            loadedModelId = nil
            loadedModelPath = nil
            loadedVisionProjectorPath = nil
            logger.info("VLM model unloaded")
        }

        /// Cancel ongoing generation
        public func cancel() {
            guard let handle = handle else { return }
            _ = rac_vlm_component_cancel(handle)
        }

        /// Check if streaming is supported
        public var supportsStreaming: Bool {
            guard let handle = handle else { return false }
            return rac_vlm_component_supports_streaming(handle) == RAC_TRUE
        }

        /// Get lifecycle state
        public var state: rac_lifecycle_state_t {
            guard let handle = handle else { return RAC_LIFECYCLE_STATE_IDLE }
            return rac_vlm_component_get_state(handle)
        }

        // MARK: - Cleanup

        /// Destroy the component
        public func destroy() {
            if let handle = handle {
                rac_vlm_component_destroy(handle)
                self.handle = nil
                loadedModelId = nil
                loadedModelPath = nil
                loadedVisionProjectorPath = nil
                logger.debug("VLM component destroyed")
            }
        }
    }
}

