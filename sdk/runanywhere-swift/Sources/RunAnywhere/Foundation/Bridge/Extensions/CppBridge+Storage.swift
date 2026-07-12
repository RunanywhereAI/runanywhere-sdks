//
//  CppBridge+Storage.swift
//  RunAnywhere SDK
//
//  Storage analyzer bridge - C++ owns business logic, Swift provides file operations
//

import CRACommons
import Foundation
import SwiftProtobuf

// MARK: - Storage Bridge

private enum StorageProtoABI {
    typealias StorageProtoFunction = @convention(c) (
        rac_storage_analyzer_handle_t?,
        rac_model_registry_handle_t?,
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t

    static let info = NativeProtoABI.load(
        "rac_storage_analyzer_info_proto",
        as: StorageProtoFunction.self
    )
    static let delete = NativeProtoABI.load(
        "rac_storage_analyzer_delete_proto",
        as: StorageProtoFunction.self
    )
}

/// Storage-analyzer pointer owned by the `Storage` actor.
private struct StorageAnalyzerHandle: @unchecked Sendable {
    let rawValue: rac_storage_analyzer_handle_t
}

extension CppBridge {

    /// Storage analyzer bridge
    /// C++ handles business logic (which models, path calculations, aggregation)
    /// Swift provides platform-specific file operations via callbacks
    public actor Storage {

        /// Shared storage analyzer instance
        public static let shared = Storage()

        private var handle: StorageAnalyzerHandle?
        private let logger = SDKLogger(category: "CppBridge.Storage")

        private init() {
            // Register callbacks and create analyzer
            var callbacks = rac_storage_callbacks_t()
            callbacks.calculate_dir_size = storageCalculateDirSizeCallback
            callbacks.get_file_size = storageGetFileSizeCallback
            callbacks.path_exists = storagePathExistsCallback
            callbacks.get_available_space = storageGetAvailableSpaceCallback
            callbacks.get_total_space = storageGetTotalSpaceCallback
            callbacks.delete_path = storageDeletePathCallback
            callbacks.is_model_loaded = nil  // C++ treats missing callback as "loaded state unavailable"
            callbacks.unload_model = nil     // C++ refuses to unload-then-delete when callback is NULL
            callbacks.user_data = nil  // We use global FileManager

            var handlePtr: rac_storage_analyzer_handle_t?
            let result = rac_storage_analyzer_create(&callbacks, &handlePtr)
            if result == RAC_SUCCESS {
                self.handle = handlePtr.map(StorageAnalyzerHandle.init(rawValue:))
                logger.debug("Storage analyzer created")
            } else {
                logger.error("Failed to create storage analyzer: \(result)")
            }
        }

        deinit {
            if let handle = handle {
                rac_storage_analyzer_destroy(handle.rawValue)
            }
        }

        // MARK: - Public API

        public func info(_ request: RAStorageInfoRequest = RAStorageInfoRequest()) async -> RAStorageInfoResult {
            do {
                return try await invokeProto(
                    request,
                    symbol: StorageProtoABI.info,
                    responseType: RAStorageInfoResult.self
                )
            } catch {
                var result = RAStorageInfoResult()
                result.success = false
                result.errorMessage = String(describing: error)
                return result
            }
        }

        public func delete(_ request: RAStorageDeleteRequest) async -> RAStorageDeleteResult {
            do {
                return try await invokeProto(
                    request,
                    symbol: StorageProtoABI.delete,
                    responseType: RAStorageDeleteResult.self
                )
            } catch {
                var result = RAStorageDeleteResult()
                result.success = false
                result.errorMessage = String(describing: error)
                return result
            }
        }

        // MARK: - Private

        private func getRegistryHandle() async -> ModelRegistryHandle? {
            // Access the registry's handle
            // Note: We need to expose this from CppBridge.ModelRegistry
            return await CppBridge.ModelRegistry.shared.getHandle()
        }

        private func invokeProto<Request: Message, Response: Message>(
            _ request: Request,
            symbol: StorageProtoABI.StorageProtoFunction?,
            responseType: Response.Type
        ) async throws -> Response {
            guard let symbol, NativeProtoABI.canReceiveProtoBuffer else {
                throw SDKException(code: .notSupported, message: NativeProtoABI.unavailableMessage, category: .internal)
            }
            guard let handle = handle, let registryHandle = await getRegistryHandle() else {
                throw SDKException(code: .initializationFailed, message: "Storage analyzer not initialized", category: .internal)
            }

            var outBuffer = rac_proto_buffer_t()
            defer { NativeProtoABI.free(&outBuffer) }

            let status = try NativeProtoABI.withSerializedBytes(request) { bytes, size in
                symbol(handle.rawValue, registryHandle.rawValue, bytes, size, &outBuffer)
            }
            guard status == RAC_SUCCESS else {
                throw SDKException(code: .processingFailed, message: "Storage proto request failed: \(status)", category: .internal)
            }
            return try NativeProtoABI.decode(responseType, from: outBuffer)
        }

    }
}

// MARK: - C Callbacks (Platform-Specific File Operations)

/// Calculate directory size — delegates to C++ file manager (single source of truth)
private func storageCalculateDirSizeCallback(
    path: UnsafePointer<CChar>?,
    userData _: UnsafeMutableRawPointer?
) -> Int64 {
    guard let path = path else { return 0 }
    let url = URL(fileURLWithPath: String(cString: path))
    return CppBridge.FileManager.calculateDirectorySize(at: url)
}

/// Get file size
private func storageGetFileSizeCallback(
    path: UnsafePointer<CChar>?,
    userData _: UnsafeMutableRawPointer?
) -> Int64 {
    guard let path = path else { return -1 }
    let url = URL(fileURLWithPath: String(cString: path))
    return FileOperationsUtilities.fileSize(at: url) ?? -1
}

/// Check if path exists
private func storagePathExistsCallback(
    path: UnsafePointer<CChar>?,
    isDirectory: UnsafeMutablePointer<rac_bool_t>?,
    userData _: UnsafeMutableRawPointer?
) -> rac_bool_t {
    guard let path = path else { return RAC_FALSE }
    let url = URL(fileURLWithPath: String(cString: path))
    let (exists, isDir) = FileOperationsUtilities.existsWithType(at: url)
    isDirectory?.pointee = isDir ? RAC_TRUE : RAC_FALSE
    return exists ? RAC_TRUE : RAC_FALSE
}

/// Get available disk space
private func storageGetAvailableSpaceCallback(userData _: UnsafeMutableRawPointer?) -> Int64 {
    do {
        let attrs = try FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        )
        return (attrs[.systemFreeSize] as? Int64) ?? 0
    } catch {
        return 0
    }
}

/// Get total disk space
private func storageGetTotalSpaceCallback(userData _: UnsafeMutableRawPointer?) -> Int64 {
    do {
        let attrs = try FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        )
        return (attrs[.systemSize] as? Int64) ?? 0
    } catch {
        return 0
    }
}

private func storageDeletePathCallback(
    path: UnsafePointer<CChar>?,
    recursive _: CInt,
    userData _: UnsafeMutableRawPointer?
) -> rac_result_t {
    guard let path else { return RAC_ERROR_INVALID_PATH }
    let url = URL(fileURLWithPath: String(cString: path))
    guard Foundation.FileManager.default.fileExists(atPath: url.path) else {
        return RAC_ERROR_FILE_NOT_FOUND
    }
    do {
        try Foundation.FileManager.default.removeItem(at: url)
        return RAC_SUCCESS
    } catch {
        return RAC_ERROR_FILE_DELETE_FAILED
    }
}

// MARK: - ModelRegistry Handle Access

extension CppBridge.ModelRegistry {
    /// Get the underlying C handle (for use by other bridges)
    func getHandle() -> CppBridge.ModelRegistryHandle? {
        handle.map(CppBridge.ModelRegistryHandle.init(rawValue:))
    }
}
