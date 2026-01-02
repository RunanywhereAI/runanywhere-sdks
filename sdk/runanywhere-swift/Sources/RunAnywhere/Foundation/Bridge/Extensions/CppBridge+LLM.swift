//
//  CppBridge+LLM.swift
//  RunAnywhere SDK
//
//  LLM component bridge - manages C++ LLM component lifecycle
//

import CRACommons
import Foundation

// MARK: - LLM Component Bridge

extension CppBridge {

    /// LLM component manager
    /// Provides thread-safe access to the C++ LLM component
    public actor LLM {

        /// Shared LLM component instance
        public static let shared = LLM()

        private var handle: rac_handle_t?
        private var loadedModelId: String?
        private let logger = SDKLogger(category: "CppBridge.LLM")

        private init() {}

        // MARK: - Handle Management

        /// Get or create the LLM component handle
        public func getHandle() throws -> rac_handle_t {
            if let handle = handle {
                return handle
            }

            var newHandle: rac_handle_t?
            let result = rac_llm_component_create(&newHandle)
            guard result == RAC_SUCCESS, let handle = newHandle else {
                throw SDKError.llm(.notInitialized, "Failed to create LLM component: \(result)")
            }

            self.handle = handle
            logger.debug("LLM component created")
            return handle
        }

        // MARK: - State

        /// Check if a model is loaded
        public var isLoaded: Bool {
            guard let handle = handle else { return false }
            return rac_llm_component_is_loaded(handle) == RAC_TRUE
        }

        /// Get the currently loaded model ID
        public var currentModelId: String? { loadedModelId }

        // MARK: - Model Lifecycle

        /// Load an LLM model
        public func loadModel(_ modelPath: String, modelId: String) throws {
            let handle = try getHandle()
            let result = modelPath.withCString { pathPtr in
                rac_llm_component_load_model(handle, pathPtr)
            }
            guard result == RAC_SUCCESS else {
                throw SDKError.llm(.modelLoadFailed, "Failed to load model: \(result)")
            }
            loadedModelId = modelId
            logger.info("LLM model loaded: \(modelId)")
        }

        /// Unload the current model
        public func unload() {
            guard let handle = handle else { return }
            rac_llm_component_cleanup(handle)
            loadedModelId = nil
            logger.info("LLM model unloaded")
        }

        /// Cancel ongoing generation
        public func cancel() {
            guard let handle = handle else { return }
            rac_llm_component_cancel(handle)
        }

        // MARK: - Cleanup

        /// Destroy the component
        public func destroy() {
            if let handle = handle {
                rac_llm_component_destroy(handle)
                self.handle = nil
                loadedModelId = nil
                logger.debug("LLM component destroyed")
            }
        }
    }
}
