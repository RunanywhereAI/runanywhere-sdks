//
//  CppBridge+ModelRegistry.swift
//  RunAnywhere SDK
//
//  Model registry bridge extension for C++ interop.
//

import CRACommons
import Foundation

// MARK: - Model Discovery Result

/// Result from model discovery scan
public struct ModelDiscoveryResult {
    public let discoveredCount: Int
    public let unregisteredCount: Int
}

// MARK: - ModelRegistry Bridge

extension CppBridge {

    /// Model registry bridge
    /// Wraps C++ rac_model_registry.h functions for in-memory model storage
    public actor ModelRegistry {

        /// Shared registry instance
        public static let shared = ModelRegistry()

        /// Internal handle - accessed by CppBridge.Storage for registry operations
        internal var handle: rac_model_registry_handle_t?
        private let logger = SDKLogger(category: "CppBridge.ModelRegistry")

        private init() {
            // Use the global C++ model registry so that models registered
            // by C++ backends (like Platform) are visible to Swift
            let globalRegistry = rac_get_model_registry()
            if globalRegistry != nil {
                self.handle = globalRegistry
                logger.debug("Using global C++ model registry")
            } else {
                logger.error("Failed to get global model registry")
            }
        }

        deinit {
            // Don't destroy the global registry - it's managed by C++
            // The handle is just a reference to the singleton
        }

        // MARK: - Save/Get Operations

        /// Save model metadata to registry
        public func save(_ model: ModelInfo) throws {
            guard let handle = handle else {
                throw SDKError.general(.initializationFailed, "Registry not initialized")
            }

            var cModel = model.toCModelInfo()
            defer { freeCModelInfo(&cModel) }

            let result = rac_model_registry_save(handle, &cModel)
            guard result == RAC_SUCCESS else {
                throw SDKError.general(.processingFailed, "Failed to save model")
            }

            logger.debug("Model saved: \(model.id)")
        }

        /// Get model metadata by ID
        public func get(modelId: String) -> ModelInfo? {
            guard let handle = handle else { return nil }

            var modelPtr: UnsafeMutablePointer<rac_model_info_t>?
            let result = modelId.withCString { mid in
                rac_model_registry_get(handle, mid, &modelPtr)
            }

            guard result == RAC_SUCCESS, let model = modelPtr else { return nil }
            defer { rac_model_info_free(model) }

            return ModelInfo(from: model.pointee)
        }

        /// Get all stored models
        public func getAll() -> [ModelInfo] {
            guard let handle = handle else { return [] }

            var modelsPtr: UnsafeMutablePointer<UnsafeMutablePointer<rac_model_info_t>?>?
            var count: Int = 0

            let result = rac_model_registry_get_all(handle, &modelsPtr, &count)
            guard result == RAC_SUCCESS, let models = modelsPtr else { return [] }
            defer { rac_model_info_array_free(models, count) }

            var modelInfos: [ModelInfo] = []
            for i in 0..<count {
                if let model = models[i] {
                    modelInfos.append(ModelInfo(from: model.pointee))
                }
            }

            return modelInfos
        }

        /// Get downloaded models
        public func getDownloaded() -> [ModelInfo] {
            guard let handle = handle else { return [] }

            var modelsPtr: UnsafeMutablePointer<UnsafeMutablePointer<rac_model_info_t>?>?
            var count: Int = 0

            let result = rac_model_registry_get_downloaded(handle, &modelsPtr, &count)
            guard result == RAC_SUCCESS, let models = modelsPtr else { return [] }
            defer { rac_model_info_array_free(models, count) }

            var modelInfos: [ModelInfo] = []
            for i in 0..<count {
                if let model = models[i] {
                    modelInfos.append(ModelInfo(from: model.pointee))
                }
            }

            return modelInfos
        }

        /// Get models for specific frameworks
        public func getByFrameworks(_ frameworks: [InferenceFramework]) -> [ModelInfo] {
            guard let handle = handle, !frameworks.isEmpty else { return [] }

            var cFrameworks = frameworks.map { $0.toCFramework() }
            var modelsPtr: UnsafeMutablePointer<UnsafeMutablePointer<rac_model_info_t>?>?
            var count: Int = 0

            let result = rac_model_registry_get_by_frameworks(
                handle,
                &cFrameworks,
                frameworks.count,
                &modelsPtr,
                &count
            )

            guard result == RAC_SUCCESS, let models = modelsPtr else { return [] }
            defer { rac_model_info_array_free(models, count) }

            var modelInfos: [ModelInfo] = []
            for i in 0..<count {
                if let model = models[i] {
                    modelInfos.append(ModelInfo(from: model.pointee))
                }
            }

            return modelInfos
        }

        // MARK: - Update Operations

        /// Update download status for a model
        public func updateDownloadStatus(modelId: String, localPath: URL?) throws {
            guard let handle = handle else {
                throw SDKError.general(.initializationFailed, "Registry not initialized")
            }

            let result: rac_result_t
            if let path = localPath {
                result = modelId.withCString { mid in
                    path.path.withCString { pathPtr in
                        rac_model_registry_update_download_status(handle, mid, pathPtr)
                    }
                }
            } else {
                result = modelId.withCString { mid in
                    rac_model_registry_update_download_status(handle, mid, nil)
                }
            }

            guard result == RAC_SUCCESS else {
                throw SDKError.general(.modelNotFound, "Model not found: \(modelId)")
            }

            logger.debug("Updated download status for: \(modelId)")
        }

        /// Update last used timestamp
        public func updateLastUsed(modelId: String) throws {
            guard let handle = handle else {
                throw SDKError.general(.initializationFailed, "Registry not initialized")
            }

            let result = modelId.withCString { mid in
                rac_model_registry_update_last_used(handle, mid)
            }

            guard result == RAC_SUCCESS else {
                throw SDKError.general(.modelNotFound, "Model not found: \(modelId)")
            }
        }

        // MARK: - Remove Operations

        /// Remove model from registry
        public func remove(modelId: String) throws {
            guard let handle = handle else {
                throw SDKError.general(.initializationFailed, "Registry not initialized")
            }

            let result = modelId.withCString { mid in
                rac_model_registry_remove(handle, mid)
            }

            guard result == RAC_SUCCESS else {
                throw SDKError.general(.modelNotFound, "Model not found: \(modelId)")
            }

            logger.debug("Model removed: \(modelId)")
        }

        // MARK: - Model Discovery

        // Discover downloaded models on the file system.
        // Scans the models directory and updates registry for models found on disk.
        // This is called automatically during SDK initialization.
        // swiftlint:disable:next cyclomatic_complexity
        public func discoverDownloadedModels() -> ModelDiscoveryResult {
            guard let handle = handle else {
                logger.warning("Discovery: Registry not initialized")
                return ModelDiscoveryResult(discoveredCount: 0, unregisteredCount: 0)
            }

            logger.info("Starting model discovery scan...")

            // Create callbacks struct
            var callbacks = rac_discovery_callbacks_t()
            callbacks.user_data = nil

            // List directory callback
            callbacks.list_directory = { path, outEntries, outCount, _ -> rac_result_t in
                guard let path = path else { return RAC_ERROR_INVALID_ARGUMENT }

                let url = URL(fileURLWithPath: String(cString: path))
                let fm = FileManager.default

                guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
                    outEntries?.pointee = nil
                    outCount?.pointee = 0
                    return RAC_SUCCESS
                }

                let count = contents.count
                outCount?.pointee = count

                if contents.isEmpty {
                    outEntries?.pointee = nil
                    return RAC_SUCCESS
                }

                // Allocate array of strings
                let entries = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: count)
                for (i, item) in contents.enumerated() {
                    let name = item.lastPathComponent
                    entries[i] = strdup(name)
                }

                outEntries?.pointee = entries
                return RAC_SUCCESS
            }

            // Free entries callback
            callbacks.free_entries = { entries, count, _ in
                guard let entries = entries else { return }
                for i in 0..<count {
                    if let entry = entries[i] {
                        free(entry)
                    }
                }
                entries.deallocate()
            }

            // Is directory callback
            callbacks.is_directory = { path, _ -> rac_bool_t in
                guard let path = path else { return RAC_FALSE }
                let pathStr = String(cString: path)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: pathStr, isDirectory: &isDir) {
                    return isDir.boolValue ? RAC_TRUE : RAC_FALSE
                }
                return RAC_FALSE
            }

            // Path exists callback
            callbacks.path_exists = { path, _ -> rac_bool_t in
                guard let path = path else { return RAC_FALSE }
                let pathStr = String(cString: path)
                return FileManager.default.fileExists(atPath: pathStr) ? RAC_TRUE : RAC_FALSE
            }

            // Is model file callback - checks for known model extensions
            callbacks.is_model_file = { path, framework, _ -> rac_bool_t in
                guard let path = path else { return RAC_FALSE }
                let pathStr = String(cString: path)
                let ext = (pathStr as NSString).pathExtension.lowercased()

                // Check based on framework
                switch framework {
                case RAC_FRAMEWORK_LLAMACPP:
                    return (ext == "gguf" || ext == "bin") ? RAC_TRUE : RAC_FALSE
                case RAC_FRAMEWORK_ONNX:
                    return (ext == "onnx" || ext == "ort") ? RAC_TRUE : RAC_FALSE
                case RAC_FRAMEWORK_FOUNDATION_MODELS, RAC_FRAMEWORK_SYSTEM_TTS:
                    // Built-in models don't need file check
                    return RAC_TRUE
                default:
                    return (ext == "gguf" || ext == "onnx" || ext == "bin" || ext == "ort") ? RAC_TRUE : RAC_FALSE
                }
            }

            // Call C++ discovery
            var result = rac_discovery_result_t()
            let status = rac_model_registry_discover_downloaded(handle, &callbacks, &result)
            defer { rac_discovery_result_free(&result) }

            if status != RAC_SUCCESS {
                logger.warning("Discovery failed with status: \(status)")
                return ModelDiscoveryResult(discoveredCount: 0, unregisteredCount: 0)
            }

            logger.info("Discovery complete: \(result.discovered_count) models found, \(result.unregistered_count) unregistered folders")
            return ModelDiscoveryResult(
                discoveredCount: Int(result.discovered_count),
                unregisteredCount: Int(result.unregistered_count)
            )
        }

        // MARK: - Helper: Convert ModelInfo to C struct

        private func freeCModelInfo(_ model: inout rac_model_info_t) {
            // Free allocated strings
            if let id = model.id { free(UnsafeMutablePointer(mutating: id)) }
            if let name = model.name { free(UnsafeMutablePointer(mutating: name)) }
            if let url = model.download_url { free(UnsafeMutablePointer(mutating: url)) }
            if let path = model.local_path { free(UnsafeMutablePointer(mutating: path)) }
            if let desc = model.description { free(UnsafeMutablePointer(mutating: desc)) }
        }
    }
}
