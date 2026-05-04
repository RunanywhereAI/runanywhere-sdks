//
//  CppBridge+ModelRegistry.swift
//  RunAnywhere SDK
//
//  Model registry bridge extension for C++ interop.
//

import CRACommons
import Darwin
import Foundation
import SwiftProtobuf

// MARK: - Model Discovery Result

/// Result from model discovery scan
public struct ModelDiscoveryResult {
    public let discoveredCount: Int
    public let unregisteredCount: Int
}

private enum RegistryProtoABI {
    typealias RegisterProto = @convention(c) (
        rac_model_registry_handle_t?, UnsafePointer<UInt8>?, Int
    ) -> rac_result_t
    typealias UpdateProto = @convention(c) (
        rac_model_registry_handle_t?, UnsafePointer<UInt8>?, Int
    ) -> rac_result_t
    typealias GetProto = @convention(c) (
        rac_model_registry_handle_t?,
        UnsafePointer<CChar>?,
        UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
        UnsafeMutablePointer<Int>?
    ) -> rac_result_t
    typealias ListProto = @convention(c) (
        rac_model_registry_handle_t?,
        UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
        UnsafeMutablePointer<Int>?
    ) -> rac_result_t
    typealias QueryProto = @convention(c) (
        rac_model_registry_handle_t?,
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
        UnsafeMutablePointer<Int>?
    ) -> rac_result_t
    typealias RemoveProto = @convention(c) (
        rac_model_registry_handle_t?, UnsafePointer<CChar>?
    ) -> rac_result_t
    typealias FreeProto = @convention(c) (UnsafeMutablePointer<UInt8>?) -> Void

    private static let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)

    private static func load<T>(_ symbolName: String, as _: T.Type) -> T? {
        guard let symbol = dlsym(defaultHandle, symbolName) else {
            return nil
        }
        return unsafeBitCast(symbol, to: T.self)
    }

    static let registerProto = load(
        "rac_model_registry_register_proto",
        as: RegisterProto.self
    )
    static let updateProto = load(
        "rac_model_registry_update_proto",
        as: UpdateProto.self
    )
    static let getProto = load(
        "rac_model_registry_get_proto",
        as: GetProto.self
    )
    static let listProto = load(
        "rac_model_registry_list_proto",
        as: ListProto.self
    )
    static let queryProto = load(
        "rac_model_registry_query_proto",
        as: QueryProto.self
    )
    static let listDownloadedProto = load(
        "rac_model_registry_list_downloaded_proto",
        as: ListProto.self
    )
    static let removeProto = load(
        "rac_model_registry_remove_proto",
        as: RemoveProto.self
    )
    static let freeProto = load(
        "rac_model_registry_proto_free",
        as: FreeProto.self
    )
}

// Top-level helper so it can be referenced from a C function pointer (no `Self` capture).
private func racIsModelFile(ext: String, filename: String, framework: rac_inference_framework_t) -> rac_bool_t {
    switch framework {
    case RAC_FRAMEWORK_LLAMACPP:
        return (ext == "gguf" || ext == "bin") ? RAC_TRUE : RAC_FALSE
    case RAC_FRAMEWORK_ONNX:
        return (ext == "onnx" || ext == "ort") ? RAC_TRUE : RAC_FALSE
    case RAC_FRAMEWORK_COREML:
        if ext == "mlmodelc" || ext == "mlpackage" || ext == "mlmodel" {
            return RAC_TRUE
        }
        if filename.contains("unet") || filename.contains("textencoder") ||
           filename.contains("vaeencoder") || filename.contains("vaedecoder") {
            return RAC_TRUE
        }
        return RAC_FALSE
    case RAC_FRAMEWORK_METALRT:
        return (ext == "safetensors" || ext == "json") ? RAC_TRUE : RAC_FALSE
    case RAC_FRAMEWORK_FOUNDATION_MODELS, RAC_FRAMEWORK_SYSTEM_TTS:
        return RAC_TRUE
    default:
        return (ext == "gguf" || ext == "onnx" || ext == "bin" || ext == "ort" || ext == "mlmodelc") ? RAC_TRUE : RAC_FALSE
    }
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
                throw SDKException.general(.initializationFailed, "Registry not initialized")
            }

            logger.info("Saving model: \(model.id), Swift framework: \(model.framework.wireString) (\(model.framework.displayName))")
            if let registerProto = RegistryProtoABI.registerProto {
                let data = try model.proto.serializedData()
                let result = data.withUnsafeBytes { rawBuffer -> rac_result_t in
                    guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                        return RAC_ERROR_INVALID_ARGUMENT
                    }
                    return registerProto(handle, bytes, rawBuffer.count)
                }

                guard result == RAC_SUCCESS else {
                    throw SDKException.general(.processingFailed, "Failed to save model via proto registry")
                }

                logger.info("Model saved successfully via proto registry: \(model.id)")
                return
            }

            var cModel = model.toCModelInfo()
            logger.info("Converted to C++: framework=\(cModel.framework) (expected CoreML=8, Unknown=99)")
            defer { freeCModelInfo(&cModel) }

            let result = rac_model_registry_save(handle, &cModel)
            guard result == RAC_SUCCESS else {
                throw SDKException.general(.processingFailed, "Failed to save model")
            }

            logger.info("Model saved successfully: \(model.id)")
        }

        /// Update existing model metadata in the registry.
        public func update(_ model: ModelInfo) throws {
            guard let handle = handle else {
                throw SDKException.general(.initializationFailed, "Registry not initialized")
            }

            if let updateProto = RegistryProtoABI.updateProto {
                let data = try model.proto.serializedData()
                let result = data.withUnsafeBytes { rawBuffer -> rac_result_t in
                    guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                        return RAC_ERROR_INVALID_ARGUMENT
                    }
                    return updateProto(handle, bytes, rawBuffer.count)
                }

                guard result == RAC_SUCCESS else {
                    throw SDKException.general(.modelNotFound, "Model not found: \(model.id)")
                }

                logger.debug("Model updated via proto registry: \(model.id)")
                return
            }

            guard get(modelId: model.id) != nil else {
                throw SDKException.general(.modelNotFound, "Model not found: \(model.id)")
            }
            try save(model)
        }

        /// Get model metadata by ID
        public func get(modelId: String) -> ModelInfo? {
            guard let handle = handle else { return nil }

            if let getProto = RegistryProtoABI.getProto,
               let freeProto = RegistryProtoABI.freeProto {
                var bytesPtr: UnsafeMutablePointer<UInt8>?
                var byteCount = 0
                let result = modelId.withCString { modelIdPtr in
                    getProto(handle, modelIdPtr, &bytesPtr, &byteCount)
                }

                guard result == RAC_SUCCESS, let bytesPtr else { return nil }
                defer { freeProto(bytesPtr) }

                let data = Data(bytes: bytesPtr, count: byteCount)
                guard let proto = try? RAModelInfo(serializedBytes: data) else {
                    logger.warning("Failed to decode model registry proto for: \(modelId)")
                    return nil
                }
                return proto.modelInfo
            }

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

            if let listProto = RegistryProtoABI.listProto,
               let freeProto = RegistryProtoABI.freeProto {
                var bytesPtr: UnsafeMutablePointer<UInt8>?
                var byteCount = 0
                let result = listProto(handle, &bytesPtr, &byteCount)

                guard result == RAC_SUCCESS, let bytesPtr else { return [] }
                defer { freeProto(bytesPtr) }

                let data = Data(bytes: bytesPtr, count: byteCount)
                guard let protoList = try? RAModelInfoList(serializedBytes: data) else {
                    logger.warning("Failed to decode model registry list proto")
                    return []
                }
                return protoList.models.map(\.modelInfo)
            }

            var modelsPtr: UnsafeMutablePointer<UnsafeMutablePointer<rac_model_info_t>?>?
            var count: Int = 0

            let result = rac_model_registry_get_all(handle, &modelsPtr, &count)
            guard result == RAC_SUCCESS, let models = modelsPtr else { return [] }
            defer { rac_model_info_array_free(models, count) }

            var modelInfos: [ModelInfo] = []
            for i in 0..<count {
                if let model = models[i] {
                    let cFramework = model.pointee.framework
                    let modelInfo = ModelInfo(from: model.pointee)
                    logger.debug("Retrieved model: \(modelInfo.id), C++ framework=\(cFramework), Swift framework=\(modelInfo.framework.wireString)")
                    modelInfos.append(modelInfo)
                }
            }

            return modelInfos
        }

        /// Get downloaded models
        public func getDownloaded() -> [ModelInfo] {
            guard let handle = handle else { return [] }

            if let listDownloadedProto = RegistryProtoABI.listDownloadedProto,
               let freeProto = RegistryProtoABI.freeProto {
                var bytesPtr: UnsafeMutablePointer<UInt8>?
                var byteCount = 0
                let result = listDownloadedProto(handle, &bytesPtr, &byteCount)

                guard result == RAC_SUCCESS, let bytesPtr else { return [] }
                defer { freeProto(bytesPtr) }

                let data = Data(bytes: bytesPtr, count: byteCount)
                guard let protoList = try? RAModelInfoList(serializedBytes: data) else {
                    logger.warning("Failed to decode downloaded model registry proto")
                    return []
                }
                return protoList.models.map(\.modelInfo)
            }

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

        /// Query models using the canonical generated proto request shape.
        public func query(_ query: RAModelQuery) -> RAModelListResult {
            guard let handle = handle else {
                return modelListResult(success: false, errorMessage: "Registry not initialized")
            }

            if let queryProto = RegistryProtoABI.queryProto,
               let freeProto = RegistryProtoABI.freeProto,
               let data = try? query.serializedData() {
                var bytesPtr: UnsafeMutablePointer<UInt8>?
                var byteCount = 0
                let result = data.withUnsafeBytes { rawBuffer -> rac_result_t in
                    let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress
                    return queryProto(handle, bytes, rawBuffer.count, &bytesPtr, &byteCount)
                }

                guard result == RAC_SUCCESS, let bytesPtr else {
                    return modelListResult(success: false, errorMessage: "Model registry query failed")
                }
                defer { freeProto(bytesPtr) }

                do {
                    let list = try RAModelInfoList(serializedBytes: Data(bytes: bytesPtr, count: byteCount))
                    return modelListResult(models: list.models)
                } catch {
                    return modelListResult(success: false, errorMessage: "Failed to decode model registry query result")
                }
            }

            let models = applyFallbackQuery(query, to: getAll()).map(\.proto)
            return modelListResult(models: models, warnings: [NativeProtoABI.unavailableMessage])
        }

        public func list(_ request: RAModelListRequest = RAModelListRequest()) -> RAModelListResult {
            if request.hasQuery {
                return query(request.query)
            }
            let models = getAll().map(\.proto)
            return modelListResult(models: models)
        }

        public func get(_ request: RAModelGetRequest) -> RAModelGetResult {
            var result = RAModelGetResult()
            guard !request.modelID.isEmpty else {
                result.found = false
                result.errorMessage = "model_id is required"
                return result
            }
            guard let model = get(modelId: request.modelID) else {
                result.found = false
                result.errorMessage = "Model not found: \(request.modelID)"
                return result
            }
            result.found = true
            result.model = model.proto
            return result
        }

        /// Get models for specific frameworks
        public func getByFrameworks(_ frameworks: [InferenceFramework]) -> [ModelInfo] {
            guard let handle = handle, !frameworks.isEmpty else { return [] }

            if RegistryProtoABI.listProto != nil,
               RegistryProtoABI.freeProto != nil {
                let frameworkSet = Set(frameworks)
                return getAll().filter { frameworkSet.contains($0.framework) }
            }

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
                throw SDKException.general(.initializationFailed, "Registry not initialized")
            }

            if RegistryProtoABI.updateProto != nil {
                guard var model = get(modelId: modelId) else {
                    throw SDKException.general(.modelNotFound, "Model not found: \(modelId)")
                }
                model.localPath = localPath
                model.updatedAt = Date()
                try update(model)
                logger.debug("Updated download status via proto registry for: \(modelId)")
                return
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
                throw SDKException.general(.modelNotFound, "Model not found: \(modelId)")
            }

            logger.debug("Updated download status for: \(modelId)")
        }

        /// Update last used timestamp
        public func updateLastUsed(modelId: String) throws {
            guard let handle = handle else {
                throw SDKException.general(.initializationFailed, "Registry not initialized")
            }

            let result = modelId.withCString { mid in
                rac_model_registry_update_last_used(handle, mid)
            }

            guard result == RAC_SUCCESS else {
                throw SDKException.general(.modelNotFound, "Model not found: \(modelId)")
            }
        }

        // MARK: - Remove Operations

        /// Remove model from registry
        public func remove(modelId: String) throws {
            guard let handle = handle else {
                throw SDKException.general(.initializationFailed, "Registry not initialized")
            }

            if let removeProto = RegistryProtoABI.removeProto {
                let result = modelId.withCString { mid in
                    removeProto(handle, mid)
                }

                guard result == RAC_SUCCESS else {
                    throw SDKException.general(.modelNotFound, "Model not found: \(modelId)")
                }

                logger.debug("Model removed via proto registry: \(modelId)")
                return
            }

            let result = modelId.withCString { mid in
                rac_model_registry_remove(handle, mid)
            }

            guard result == RAC_SUCCESS else {
                throw SDKException.general(.modelNotFound, "Model not found: \(modelId)")
            }

            logger.debug("Model removed: \(modelId)")
        }

        // MARK: - Model Discovery

        // Discover downloaded models on the file system.
        // Scans the models directory and updates registry for models found on disk.
        // This is called automatically during SDK initialization.
        public func discoverDownloadedModels() -> ModelDiscoveryResult {
            guard let handle = handle else {
                logger.warning("Discovery: Registry not initialized")
                return ModelDiscoveryResult(discoveredCount: 0, unregisteredCount: 0)
            }

            logger.info("Starting model discovery scan...")

            var callbacks = makeDiscoveryCallbacks()

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

        // MARK: - Refresh (T4.9)

        /// Unified registry refresh — bridges `rac_model_registry_refresh`.
        ///
        /// Each flag is independent:
        ///   - `includeRemoteCatalog`: fetches the model assignment catalog
        ///     from the backend (requires assignment callbacks to have been
        ///     registered at SDK init).
        ///   - `rescanLocal`: rescans the on-disk model directories and
        ///     links any newly downloaded models back to the registry.
        ///   - `pruneOrphans`: clears `localPath` on models whose recorded
        ///     path no longer exists on disk.
        @discardableResult
        public func refresh(
            includeRemoteCatalog: Bool = true,
            rescanLocal: Bool = true,
            pruneOrphans: Bool = false
        ) -> Bool {
            guard let handle = handle else {
                logger.warning("Refresh: Registry not initialized")
                return false
            }

            logger.info("Refreshing registry: remote=\(includeRemoteCatalog), rescan=\(rescanLocal), prune=\(pruneOrphans)")

            var callbacks = makeDiscoveryCallbacks()
            let needsCallbacks = rescanLocal || pruneOrphans
            let status = withUnsafePointer(to: &callbacks) { cbPtr -> rac_result_t in
                var opts = rac_model_registry_refresh_opts_t()
                opts.include_remote_catalog = includeRemoteCatalog ? RAC_TRUE : RAC_FALSE
                opts.rescan_local = rescanLocal ? RAC_TRUE : RAC_FALSE
                opts.prune_orphans = pruneOrphans ? RAC_TRUE : RAC_FALSE
                opts.discovery_callbacks = needsCallbacks ? cbPtr : nil
                return rac_model_registry_refresh(handle, opts)
            }

            if status != RAC_SUCCESS {
                logger.warning("Refresh returned non-success status: \(status)")
                return false
            }
            return true
        }

        // MARK: - Discovery Callbacks

        private func makeDiscoveryCallbacks() -> rac_discovery_callbacks_t {
            var callbacks = rac_discovery_callbacks_t()
            callbacks.user_data = nil
            callbacks.list_directory = { path, outEntries, outCount, _ -> rac_result_t in
                guard let path = path else { return RAC_ERROR_INVALID_ARGUMENT }

                let url = URL(fileURLWithPath: String(cString: path))
                let fm = Foundation.FileManager.default

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

                let entries = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: count)
                for (i, item) in contents.enumerated() {
                    entries[i] = strdup(item.lastPathComponent)
                }

                outEntries?.pointee = entries
                return RAC_SUCCESS
            }

            callbacks.free_entries = { entries, count, _ in
                guard let entries = entries else { return }
                for i in 0..<count {
                    if let entry = entries[i] {
                        free(entry)
                    }
                }
                entries.deallocate()
            }

            callbacks.is_directory = { path, _ -> rac_bool_t in
                guard let path = path else { return RAC_FALSE }
                let pathStr = String(cString: path)
                var isDir: ObjCBool = false
                if Foundation.FileManager.default.fileExists(atPath: pathStr, isDirectory: &isDir) {
                    return isDir.boolValue ? RAC_TRUE : RAC_FALSE
                }
                return RAC_FALSE
            }

            callbacks.path_exists = { path, _ -> rac_bool_t in
                guard let path = path else { return RAC_FALSE }
                let pathStr = String(cString: path)
                return Foundation.FileManager.default.fileExists(atPath: pathStr) ? RAC_TRUE : RAC_FALSE
            }

            callbacks.is_model_file = { path, framework, _ -> rac_bool_t in
                guard let path = path else { return RAC_FALSE }
                let pathStr = String(cString: path)
                let ext = (pathStr as NSString).pathExtension.lowercased()
                let filename = (pathStr as NSString).lastPathComponent.lowercased()
                return racIsModelFile(ext: ext, filename: filename, framework: framework)
            }

            return callbacks
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

        private func modelListResult(
            success: Bool = true,
            models: [RAModelInfo] = [],
            warnings: [String] = [],
            errorMessage: String = ""
        ) -> RAModelListResult {
            var result = RAModelListResult()
            result.success = success
            var list = RAModelInfoList()
            list.models = models
            result.models = list
            if !warnings.isEmpty {
                result.errorMessage = warnings.joined(separator: "; ")
            } else {
                result.errorMessage = errorMessage
            }
            return result
        }

        private func applyFallbackQuery(_ query: RAModelQuery, to models: [ModelInfo]) -> [ModelInfo] {
            var filtered = models.filter { model in
                if query.hasFramework, query.framework != .unspecified, model.framework != query.framework {
                    return false
                }
                if query.hasCategory, query.category != .unspecified, model.category != query.category {
                    return false
                }
                if query.hasFormat, query.format != .unspecified, model.format != query.format {
                    return false
                }
                if query.hasSource, query.source != .unspecified, model.source != query.source {
                    return false
                }
                if query.hasDownloadedOnly, query.downloadedOnly, model.localPath == nil {
                    return false
                }
                if query.hasAvailableOnly, query.availableOnly, !model.isAvailable {
                    return false
                }
                if query.hasMaxSizeBytes, query.maxSizeBytes > 0 {
                    let size = model.downloadSize ?? 0
                    if size > query.maxSizeBytes {
                        return false
                    }
                }
                if !query.searchQuery.isEmpty {
                    let needle = query.searchQuery.lowercased()
                    let haystack = [
                        model.id,
                        model.name,
                        model.description ?? "",
                    ].joined(separator: " ").lowercased()
                    if !haystack.contains(needle) {
                        return false
                    }
                }
                return true
            }

            guard query.hasSortField, query.sortField != .unspecified else {
                return filtered
            }
            let descending = query.hasSortOrder && query.sortOrder == .descending
            filtered.sort { lhs, rhs in
                let orderedAscending: Bool
                switch query.sortField {
                case .name:
                    orderedAscending = lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                case .createdAtUnixMs:
                    orderedAscending = lhs.createdAt < rhs.createdAt
                case .updatedAtUnixMs:
                    orderedAscending = lhs.updatedAt < rhs.updatedAt
                case .downloadSizeBytes:
                    orderedAscending = (lhs.downloadSize ?? 0) < (rhs.downloadSize ?? 0)
                default:
                    orderedAscending = lhs.id < rhs.id
                }
                return descending ? !orderedAscending : orderedAscending
            }
            return filtered
        }
    }
}
