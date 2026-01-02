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
                throw SDKError.stt(.notInitialized, "Failed to create STT component: \(result)")
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
        public func loadModel(_ modelPath: String, modelId: String) throws {
            let handle = try getHandle()
            let result = modelPath.withCString { pathPtr in
                rac_stt_component_load_model(handle, pathPtr)
            }
            guard result == RAC_SUCCESS else {
                throw SDKError.stt(.modelLoadFailed, "Failed to load model: \(result)")
            }
            loadedModelId = modelId
            logger.info("STT model loaded: \(modelId)")
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
