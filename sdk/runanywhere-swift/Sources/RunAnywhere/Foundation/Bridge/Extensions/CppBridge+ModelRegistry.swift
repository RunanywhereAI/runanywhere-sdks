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
    typealias RegistryRequestProto = @convention(c) (
        rac_model_registry_handle_t?,
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t
    typealias FreeProto = @convention(c) (UnsafeMutablePointer<UInt8>?) -> Void

    private static func load<T>(_ symbolName: String, as _: T.Type) -> T? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), symbolName) else {
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
    static let discoverProto = NativeProtoABI.load(
        "rac_model_registry_discover_proto",
        as: RegistryRequestProto.self
    )
    static let refreshProto = NativeProtoABI.load(
        "rac_model_registry_refresh_proto",
        as: RegistryRequestProto.self
    )
    static let importProto = NativeProtoABI.load(
        "rac_model_registry_import_proto",
        as: RegistryRequestProto.self
    )
    // Canonical registration factories (global registry, no handle): commons
    // owns id/name/format/artifact derivation, hf.co/org/repo[:quant]
    // resolution, and merge-on-reseed download-state preservation.
    static let registerFromUrlProto = NativeProtoABI.load(
        "rac_register_model_from_url_proto",
        as: NativeProtoABI.ProtoRequest.self
    )
    static let registerMultiFileProto = NativeProtoABI.load(
        "rac_register_multi_file_model_proto",
        as: NativeProtoABI.ProtoRequest.self
    )
    static let freeProto = load(
        "rac_model_registry_proto_free",
        as: FreeProto.self
    )
}

// MARK: - ModelRegistry Bridge

extension CppBridge {

    /// Global model-registry pointer owned by commons for the process lifetime.
    /// The wrapper is the only representation allowed across actor boundaries.
    struct ModelRegistryHandle: @unchecked Sendable {
        let rawValue: rac_model_registry_handle_t
    }

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
        public func save(_ model: RAModelInfo) throws {
            guard let handle = handle else {
                throw SDKException(code: .initializationFailed, message: "Registry not initialized", category: .internal)
            }

            logger.info("Saving model: \(model.id), Swift framework: \(model.framework.wireString) (\(model.framework.displayName))")
            guard let registerProto = RegistryProtoABI.registerProto else {
                throw SDKException(
                    code: .notSupported,
                    message: NativeProtoABI.missingSymbolMessage("rac_model_registry_register_proto"),
                    category: .internal
                )
            }

            let data = try model.serializedData()
            let result = data.withUnsafeBytes { rawBuffer -> rac_result_t in
                guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    return RAC_ERROR_INVALID_ARGUMENT
                }
                return registerProto(handle, bytes, rawBuffer.count)
            }

            guard result == RAC_SUCCESS else {
                throw SDKException(code: .processingFailed, message: "Failed to save model via proto registry", category: .internal)
            }

            logger.info("Model saved successfully via proto registry: \(model.id)")
        }

        /// Update existing model metadata in the registry.
        public func update(_ model: RAModelInfo) throws {
            guard let handle = handle else {
                throw SDKException(code: .initializationFailed, message: "Registry not initialized", category: .internal)
            }

            guard let updateProto = RegistryProtoABI.updateProto else {
                throw SDKException(
                    code: .notSupported,
                    message: NativeProtoABI.missingSymbolMessage("rac_model_registry_update_proto"),
                    category: .internal
                )
            }

            let data = try model.serializedData()
            let result = data.withUnsafeBytes { rawBuffer -> rac_result_t in
                guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    return RAC_ERROR_INVALID_ARGUMENT
                }
                return updateProto(handle, bytes, rawBuffer.count)
            }

            guard result == RAC_SUCCESS else {
                throw SDKException(code: .modelNotFound, message: "Model not found: \(model.id)", category: .internal)
            }

            logger.debug("Model updated via proto registry: \(model.id)")
        }

        /// Get model metadata by ID
        public func get(modelId: String) -> RAModelInfo? {
            guard let handle = handle else { return nil }

            guard let getProto = RegistryProtoABI.getProto,
                  let freeProto = RegistryProtoABI.freeProto else {
                logger.warning(NativeProtoABI.missingSymbolMessage("rac_model_registry_get_proto"))
                return nil
            }

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
            return proto
        }

        /// Get all stored models
        public func getAll() -> [RAModelInfo] {
            guard let handle = handle else { return [] }

            guard let listProto = RegistryProtoABI.listProto,
                  let freeProto = RegistryProtoABI.freeProto else {
                logger.warning(NativeProtoABI.missingSymbolMessage("rac_model_registry_list_proto"))
                return []
            }

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
            return protoList.models
        }

        /// Get downloaded models
        public func getDownloaded() -> [RAModelInfo] {
            guard let handle = handle else { return [] }

            guard let listDownloadedProto = RegistryProtoABI.listDownloadedProto,
                  let freeProto = RegistryProtoABI.freeProto else {
                logger.warning(NativeProtoABI.missingSymbolMessage("rac_model_registry_list_downloaded_proto"))
                return []
            }

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
            return protoList.models
        }

        /// Query models using the canonical generated proto request shape.
        public func query(_ query: RAModelQuery) -> RAModelListResult {
            guard let handle = handle else {
                return modelListResult(success: false, errorMessage: "Registry not initialized")
            }

            guard let queryProto = RegistryProtoABI.queryProto,
                  let freeProto = RegistryProtoABI.freeProto else {
                return modelListResult(
                    success: false,
                    errorMessage: NativeProtoABI.missingSymbolMessage("rac_model_registry_query_proto")
                )
            }

            guard let data = try? query.serializedData() else {
                return modelListResult(success: false, errorMessage: "Failed to serialize model query")
            }

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

        public func list(_ request: RAModelListRequest = RAModelListRequest()) -> RAModelListResult {
            if request.hasQuery {
                return query(request.query)
            }
            let models = getAll()
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
            result.model = model
            return result
        }

        /// Get models for specific frameworks
        public func getByFrameworks(_ frameworks: [InferenceFramework]) -> [RAModelInfo] {
            guard !frameworks.isEmpty else { return [] }
            let frameworkSet = Set(frameworks)
            return getAll().filter { frameworkSet.contains($0.framework) }
        }

        // MARK: - Update Operations

        /// Update download status for a model
        public func updateDownloadStatus(modelId: String, localPath: URL?) throws {
            guard var model = get(modelId: modelId) else {
                throw SDKException(code: .modelNotFound, message: "Model not found: \(modelId)", category: .internal)
            }

            model.setLocalPath(localPath)
            model.updatedAtUnixMs = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
            try update(model)
            logger.debug("Updated download status via proto registry for: \(modelId)")
        }

        /// Update last used timestamp
        public func updateLastUsed(modelId: String) throws {
            guard var model = get(modelId: modelId) else {
                throw SDKException(code: .modelNotFound, message: "Model not found: \(modelId)", category: .internal)
            }

            model.lastUsedAtUnixMs = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
            model.usageCount += 1
            try update(model)
        }

        // MARK: - Remove Operations

        /// Remove model from registry
        public func remove(modelId: String) throws {
            guard let handle = handle else {
                throw SDKException(code: .initializationFailed, message: "Registry not initialized", category: .internal)
            }

            guard let removeProto = RegistryProtoABI.removeProto else {
                throw SDKException(
                    code: .notSupported,
                    message: NativeProtoABI.missingSymbolMessage("rac_model_registry_remove_proto"),
                    category: .internal
                )
            }

            let result = modelId.withCString { mid in
                removeProto(handle, mid)
            }

            guard result == RAC_SUCCESS else {
                throw SDKException(code: .modelNotFound, message: "Model not found: \(modelId)", category: .internal)
            }

            logger.debug("Model removed via proto registry: \(modelId)")
        }

        // MARK: - Model Discovery

        // Discover downloaded models on the file system.
        // Reports registry entries with normalized local paths using the portable
        // serialized-proto discovery surface.
        // This is called automatically during SDK initialization.
        public func discoverDownloadedModels(
            _ request: RAModelDiscoveryRequest? = nil
        ) -> RAModelDiscoveryResult {
            let request = request ?? Self.defaultDiscoveryRequest()
            do {
                let result: RAModelDiscoveryResult = try invokeRegistryProto(
                    request,
                    symbol: RegistryProtoABI.discoverProto,
                    symbolName: "rac_model_registry_discover_proto",
                    responseType: RAModelDiscoveryResult.self
                )
                logger.info("Discovery complete via proto: \(result.linkedCount) models linked, \(result.scannedCount) scanned")
                return result
            } catch {
                logger.warning("Discovery proto failed: \(error)")
                var result = RAModelDiscoveryResult()
                result.success = false
                result.errorMessage = String(describing: error)
                return result
            }
        }

        // MARK: - Refresh (T4.9)

        /// Unified registry refresh through the serialized
        /// `RAModelRegistryRefreshRequest` C ABI.
        public func refresh(
            _ request: RAModelRegistryRefreshRequest
        ) -> RAModelRegistryRefreshResult {
            do {
                return try invokeRegistryProto(
                    request,
                    symbol: RegistryProtoABI.refreshProto,
                    symbolName: "rac_model_registry_refresh_proto",
                    responseType: RAModelRegistryRefreshResult.self
                )
            } catch {
                logger.warning("Refresh proto failed: \(error)")
                var result = RAModelRegistryRefreshResult()
                result.success = false
                result.errorMessage = String(describing: error)
                return result
            }
        }

        /// Import platform-normalized local model metadata through the
        /// generated registry import contract. Swift supplies stable paths after
        /// URLSession/file-picker/sandbox work; commons owns the registry merge.
        /// Register a model from a URL or Hugging Face reference through the
        /// canonical commons factory. Commons derives id/name/format/artifact,
        /// resolves hf.co/org/repo[:quant] refs (quant selection, mmproj
        /// pairing, shard sets, checksums), and preserves prior download state
        /// on catalog re-seed (merge-not-replace).
        public func registerFromUrl(_ request: RARegisterModelFromUrlRequest) throws -> RAModelInfo {
            try NativeProtoABI.invoke(
                request,
                symbol: RegistryProtoABI.registerFromUrlProto,
                symbolName: "rac_register_model_from_url_proto",
                responseType: RAModelInfo.self
            )
        }

        /// Register a multi-file model (VLM gguf+mmproj pairs, embedding
        /// model+vocab sets) through the canonical commons factory — replaces
        /// the hand-built MultiFileArtifact ModelInfo assembly.
        public func registerMultiFile(_ request: RARegisterMultiFileModelRequest) throws -> RAModelInfo {
            try NativeProtoABI.invoke(
                request,
                symbol: RegistryProtoABI.registerMultiFileProto,
                symbolName: "rac_register_multi_file_model_proto",
                responseType: RAModelInfo.self
            )
        }

        public func importModel(_ request: RAModelImportRequest) throws -> RAModelImportResult {
            try invokeRegistryProto(
                request,
                symbol: RegistryProtoABI.importProto,
                symbolName: "rac_model_registry_import_proto",
                responseType: RAModelImportResult.self
            )
        }

        private func modelListResult(
            success: Bool = true,
            models: [RAModelInfo] = [],
            errorMessage: String = ""
        ) -> RAModelListResult {
            var result = RAModelListResult()
            result.success = success
            var list = RAModelInfoList()
            list.models = models
            result.models = list
            result.errorMessage = errorMessage
            return result
        }

        private func invokeRegistryProto<Request: Message, Response: Message>(
            _ request: Request,
            symbol: RegistryProtoABI.RegistryRequestProto?,
            symbolName: String,
            responseType: Response.Type
        ) throws -> Response {
            guard let handle else {
                throw SDKException(code: .initializationFailed, message: "Registry not initialized", category: .internal)
            }
            guard let symbol, NativeProtoABI.canReceiveProtoBuffer else {
                throw SDKException(
                    code: .notSupported,
                    message: NativeProtoABI.missingSymbolMessage(symbolName),
                    category: .internal
                )
            }

            var outBuffer = rac_proto_buffer_t()
            defer { NativeProtoABI.free(&outBuffer) }

            let status = try NativeProtoABI.withSerializedBytes(request) { bytes, size in
                symbol(handle, bytes, size, &outBuffer)
            }
            guard status == RAC_SUCCESS else {
                let message = outBuffer.error_message.map { String(cString: $0) }
                    ?? "Registry proto request failed: \(symbolName) rc=\(status)"
                throw SDKException(code: .processingFailed, message: message, category: .internal)
            }
            return try NativeProtoABI.decode(responseType, from: outBuffer)
        }

        private static func defaultDiscoveryRequest() -> RAModelDiscoveryRequest {
            var request = RAModelDiscoveryRequest()
            request.linkDownloaded = true
            request.recursive = true
            request.includeUserImports = true
            var query = RAModelQuery()
            query.downloadedOnly = true
            request.query = query
            return request
        }
    }
}
