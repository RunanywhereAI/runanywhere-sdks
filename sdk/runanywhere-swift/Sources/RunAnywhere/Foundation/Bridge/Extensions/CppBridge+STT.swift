//
//  CppBridge+STT.swift
//  RunAnywhere SDK
//
//  STT component bridge - manages C++ STT component lifecycle
//

import CRACommons
import Foundation

// MARK: - STT Component Bridge

extension CppBridge {

    /// STT component manager
    /// Provides thread-safe access to the C++ STT component
    public actor STT {

        /// Shared STT component instance
        public static let shared = STT()

        private var handle: rac_handle_t?
        private var loadedModelId: String?
        private let logger = SDKLogger(category: "CppBridge.STT")

        private init() {}

        // MARK: - Handle Management

        /// Get or create the STT component handle
        public func getHandle() throws -> rac_handle_t {
            if let handle = handle {
                return handle
            }

            var newHandle: rac_handle_t?
            let result = rac_stt_component_create(&newHandle)
            guard result == RAC_SUCCESS, let handle = newHandle else {
                throw SDKException.stt(.notInitialized, "Failed to create STT component: \(result)")
            }

            self.handle = handle
            logger.debug("STT component created")
            return handle
        }

        // MARK: - State

        /// Check if a model is loaded
        public var isLoaded: Bool {
            guard let handle = handle else { return false }
            return rac_stt_component_is_loaded(handle) == RAC_TRUE
        }

        /// Get the currently loaded model ID
        public var currentModelId: String? { loadedModelId }

        /// Check if streaming is supported
        public var supportsStreaming: Bool {
            guard let handle = handle else { return false }
            return rac_stt_component_supports_streaming(handle) == RAC_TRUE
        }

        // MARK: - Model Lifecycle

        /// Load an STT model
        public func loadModel(
            _ modelPath: String,
            modelId: String,
            modelName: String,
            framework: rac_inference_framework_t = RAC_FRAMEWORK_UNKNOWN
        ) throws {
            // Skip if the same model is already loaded — avoids redundant
            // backend model-compilation/load work.
            guard loadedModelId != modelId else {
                logger.info("Model already loaded: \(modelId)")
                return
            }

            let handle = try getHandle()

            // Configure the component with the correct framework so telemetry events
            // carry the real framework value instead of "unknown".
            if framework != RAC_FRAMEWORK_UNKNOWN {
                var config = RAC_STT_CONFIG_DEFAULT
                config.preferred_framework = Int32(framework.rawValue)
                let configResult = rac_stt_component_configure(handle, &config)
                if configResult != RAC_SUCCESS {
                    logger.warning("Failed to configure STT framework: \(configResult)")
                }
            }

            let result = modelPath.withCString { pathPtr in
                modelId.withCString { idPtr in
                    modelName.withCString { namePtr in
                        rac_stt_component_load_model(handle, pathPtr, idPtr, namePtr)
                    }
                }
            }
            guard result == RAC_SUCCESS else {
                throw SDKException.stt(.modelLoadFailed, "Failed to load model: \(result)")
            }
            loadedModelId = modelId
            logger.info("STT model loaded: \(modelId)")
        }

        /// Load an STT model from a `RAModelLoadResult` returned by the proto-backed
        /// lifecycle API. Mirrors `CppBridge.VLM.loadModel(from:)` so the Swift
        /// component actor's `isLoaded` flag tracks the lifecycle service's state
        /// after `RunAnywhere.loadModel(...)` returns `success=true`.
        func loadModel(from result: RAModelLoadResult, modelName: String? = nil) throws {
            if loadedModelId == result.modelID {
                return
            }
            guard result.success else {
                throw SDKException.stt(
                    .modelLoadFailed,
                    result.errorMessage.isEmpty ? "STT lifecycle load failed" : result.errorMessage
                )
            }
            guard let primaryPath = result.lifecyclePrimaryArtifactPath else {
                throw SDKException.stt(
                    .modelLoadFailed,
                    "STT lifecycle result did not include a primary model artifact"
                )
            }

            let framework: rac_inference_framework_t
            switch result.framework {
            case .onnx:
                framework = RAC_FRAMEWORK_ONNX
            case .sherpa:
                framework = RAC_FRAMEWORK_SHERPA
            default:
                framework = RAC_FRAMEWORK_UNKNOWN
            }

            try loadModel(
                primaryPath,
                modelId: result.modelID,
                modelName: modelName ?? result.modelID,
                framework: framework
            )
        }

        /// Unload the current model
        public func unload() {
            guard let handle = handle else { return }
            rac_stt_component_cleanup(handle)
            loadedModelId = nil
            logger.info("STT model unloaded")
        }

        // MARK: - Cleanup

        /// Destroy the component
        public func destroy() {
            if let handle = handle {
                rac_stt_component_destroy(handle)
                self.handle = nil
                loadedModelId = nil
                logger.debug("STT component destroyed")
            }
        }
    }
}
