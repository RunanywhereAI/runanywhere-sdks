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

        // MARK: - LoRA Adapter Management

        /// Load and apply a LoRA adapter to the currently loaded model
        public func loadLoraAdapter(_ config: LoRAAdapterConfig) throws {
            let handle = try getHandle()
            let result = config.path.withCString { pathPtr in
                rac_llm_component_load_lora(handle, pathPtr, config.scale)
            }
            guard result == RAC_SUCCESS else {
                throw SDKError.llm(.modelLoadFailed, "Failed to load LoRA adapter: \(result)")
            }
            logger.info("LoRA adapter loaded: \(config.path) (scale=\(config.scale))")
        }

        /// Remove a specific LoRA adapter by path
        public func removeLoraAdapter(_ path: String) throws {
            guard let handle = handle else {
                throw SDKError.llm(.invalidState, "No LLM component active")
            }
            let result = path.withCString { pathPtr in
                rac_llm_component_remove_lora(handle, pathPtr)
            }
            guard result == RAC_SUCCESS else {
                throw SDKError.llm(.invalidState, "Failed to remove LoRA adapter: \(result)")
            }
            logger.info("LoRA adapter removed: \(path)")
        }

        /// Remove all LoRA adapters
        public func clearLoraAdapters() throws {
            guard let handle = handle else {
                throw SDKError.llm(.invalidState, "No LLM component active")
            }
            let result = rac_llm_component_clear_lora(handle)
            guard result == RAC_SUCCESS else {
                throw SDKError.llm(.invalidState, "Failed to clear LoRA adapters: \(result)")
            }
            logger.info("All LoRA adapters cleared")
        }

        /// Check if a LoRA adapter is compatible with the currently loaded model
        public func checkLoraCompatibility(loraPath: String) -> LoraCompatibilityResult {
            guard let handle = handle else {
                return LoraCompatibilityResult(isCompatible: false, error: "No LLM component active")
            }
            var errorPtr: UnsafeMutablePointer<CChar>?
            let result = loraPath.withCString { pathPtr in
                rac_llm_component_check_lora_compat(handle, pathPtr, &errorPtr)
            }
            if result == RAC_SUCCESS {
                return LoraCompatibilityResult(isCompatible: true)
            }
            let errorMsg = errorPtr.map { String(cString: $0) }
            if let ptr = errorPtr { rac_free(ptr) }
            return LoraCompatibilityResult(isCompatible: false, error: errorMsg)
        }

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
                  let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                logger.error("Failed to parse LoRA info JSON")
                return []
            }

            return array.compactMap { dict in
                guard let path = dict["path"] as? String,
                      let scale = dict["scale"] as? Double,
                      let applied = dict["applied"] as? Bool else { return nil }
                return LoRAAdapterInfo(path: path, scale: Float(scale), applied: applied)
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
