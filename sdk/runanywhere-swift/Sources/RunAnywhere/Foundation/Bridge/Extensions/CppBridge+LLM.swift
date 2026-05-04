//
//  CppBridge+LLM.swift
//  RunAnywhere SDK
//
//  LLM component bridge - manages C++ LLM component lifecycle
//

import CRACommons
import Foundation

// MARK: - Decodable JSON Entries

/// Decoded entry from `rac_llm_component_get_lora_info` JSON payload.
private struct LoRAInfoJSONEntry: Decodable {
    let path: String
    let scale: Double
    let applied: Bool
}

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
                throw SDKException.llm(.notInitialized, "Failed to create LLM component: \(result)")
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
        public func loadModel(_ modelPath: String, modelId: String, modelName: String) throws {
            let handle = try getHandle()
            let result = modelPath.withCString { pathPtr in
                modelId.withCString { idPtr in
                    modelName.withCString { namePtr in
                        rac_llm_component_load_model(handle, pathPtr, idPtr, namePtr)
                    }
                }
            }
            guard result == RAC_SUCCESS else {
                throw SDKException.llm(.modelLoadFailed, "Failed to load model: \(result)")
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

        // MARK: - LoRA Adapter Management

        /// Get info about all loaded LoRA adapters
        public func getLoadedLoraAdapters() throws -> [LoRAAdapterInfo] {
            guard let handle = handle else { return [] }
            var jsonPtr: UnsafeMutablePointer<CChar>?
            let result = rac_llm_component_get_lora_info(handle, &jsonPtr)
            guard result == RAC_SUCCESS, let ptr = jsonPtr else {
                return []
            }
            defer { rac_free(ptr) }

            let jsonString = String(cString: ptr)
            guard let data = jsonString.data(using: .utf8),
                  let entries = try? JSONDecoder().decode([LoRAInfoJSONEntry].self, from: data) else {
                logger.error("Failed to parse LoRA info JSON")
                return []
            }

            return entries.map { entry in
                LoRAAdapterInfo(path: entry.path, scale: Float(entry.scale), applied: entry.applied)
            }
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
