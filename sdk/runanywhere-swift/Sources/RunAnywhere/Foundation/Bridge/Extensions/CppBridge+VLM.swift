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
        private var loadedMmprojPath: String?
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
                throw SDKError.vlm(.notInitialized, "Failed to create VLM component: \(result)")
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

        /// Get the currently loaded mmproj path
        public var currentMmprojPath: String? { loadedMmprojPath }

        // MARK: - Model Lifecycle

        /// Load a VLM model
        /// - Parameters:
        ///   - modelPath: Path to the main model file (GGUF)
        ///   - mmprojPath: Path to the vision projector file (required for llama.cpp VLM)
        ///   - modelId: Model identifier for telemetry
        ///   - modelName: Human-readable model name
        public func loadModel(
            _ modelPath: String,
            mmprojPath: String?,
            modelId: String,
            modelName: String
        ) throws {
            let handle = try getHandle()

            let result: rac_result_t
            if let mmprojPath = mmprojPath {
                result = modelPath.withCString { pathPtr in
                    mmprojPath.withCString { mmprojPtr in
                        modelId.withCString { idPtr in
                            modelName.withCString { namePtr in
                                rac_vlm_component_load_model(handle, pathPtr, mmprojPtr, idPtr, namePtr)
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
                throw SDKError.vlm(.modelLoadFailed, "Failed to load VLM model: \(result)")
            }

            loadedModelId = modelId
            loadedModelPath = modelPath
            loadedMmprojPath = mmprojPath
            logger.info("VLM model loaded: \(modelId)")
        }

        /// Load a VLM model by ID using the C++ model registry for path resolution.
        /// The C++ layer handles finding the main model and mmproj files automatically.
        ///
        /// - Parameter modelId: Model identifier (must be registered in the global model registry)
        public func loadModelById(_ modelId: String) throws {
            let handle = try getHandle()

            let result = modelId.withCString { idPtr in
                rac_vlm_component_load_model_by_id(handle, idPtr)
            }

            guard result == RAC_SUCCESS else {
                throw SDKError.vlm(.modelLoadFailed, "Failed to load VLM model by ID: \(modelId) (error: \(result))")
            }

            loadedModelId = modelId
            logger.info("VLM model loaded by ID: \(modelId)")
        }

        /// Unload the current model
        public func unload() {
            guard let handle = handle else { return }
            rac_vlm_component_cleanup(handle)
            loadedModelId = nil
            loadedModelPath = nil
            loadedMmprojPath = nil
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
                loadedMmprojPath = nil
                logger.debug("VLM component destroyed")
            }
        }
    }
}

// MARK: - SDKError VLM Extension

extension SDKError {

    /// VLM-specific error codes
    public enum VLMErrorCode: Int, Sendable {
        case notInitialized = 1
        case modelLoadFailed = 2
        case processingFailed = 3
        case invalidImage = 4
        case cancelled = 5
    }

    /// Create a VLM error
    public static func vlm(_ code: VLMErrorCode, _ message: String) -> SDKError {
        return SDKError.general(.unknown, "VLM[\(code.rawValue)]: \(message)")
    }
}
