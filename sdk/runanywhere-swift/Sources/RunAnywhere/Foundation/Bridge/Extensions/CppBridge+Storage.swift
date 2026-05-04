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
    static let availability = NativeProtoABI.load(
        "rac_storage_analyzer_availability_proto",
        as: StorageProtoFunction.self
    )
    static let deletePlan = NativeProtoABI.load(
        "rac_storage_analyzer_delete_plan_proto",
        as: StorageProtoFunction.self
    )
    static let delete = NativeProtoABI.load(
        "rac_storage_analyzer_delete_proto",
        as: StorageProtoFunction.self
    )
}

extension CppBridge {

    /// Storage analyzer bridge
    /// C++ handles business logic (which models, path calculations, aggregation)
    /// Swift provides platform-specific file operations via callbacks
    public actor Storage {

        /// Shared storage analyzer instance
        public static let shared = Storage()

        private var handle: rac_storage_analyzer_handle_t?
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
            callbacks.is_model_loaded = storageIsModelLoadedCallback
            callbacks.unload_model = storageUnloadModelCallback
            callbacks.user_data = nil  // We use global FileManager

            var handlePtr: rac_storage_analyzer_handle_t?
            let result = rac_storage_analyzer_create(&callbacks, &handlePtr)
            if result == RAC_SUCCESS {
                self.handle = handlePtr
                logger.debug("Storage analyzer created")
            } else {
                logger.error("Failed to create storage analyzer: \(result)")
            }
        }

        deinit {
            if let handle = handle {
                rac_storage_analyzer_destroy(handle)
            }
        }

        // MARK: - Public API

        /// Analyze overall storage
        /// C++ iterates models, calculates paths, calls Swift for sizes
        public func analyzeStorage() async -> StorageInfo {
            guard let handle = handle else {
                return .empty
            }

            // Get registry handle from CppBridge.ModelRegistry
            // Note: We need access to the registry's handle
            let registryHandle = await getRegistryHandle()
            guard let regHandle = registryHandle else {
                return .empty
            }

            var cInfo = rac_storage_info_t()
            let result = rac_storage_analyzer_analyze(handle, regHandle, &cInfo)

            guard result == RAC_SUCCESS else {
                logger.error("Storage analysis failed: \(result)")
                return .empty
            }

            defer { rac_storage_info_free(&cInfo) }

            // Convert C++ result to Swift types
            return StorageInfo(from: cInfo)
        }

        /// Get storage metrics for a specific model
        public func getModelStorageMetrics(
            modelId: String,
            framework: InferenceFramework
        ) async -> ModelStorageMetrics? {
            guard let handle = handle else { return nil }

            let registryHandle = await getRegistryHandle()
            guard let regHandle = registryHandle else { return nil }

            var cMetrics = rac_model_storage_metrics_t()
            let result = modelId.withCString { mid in
                rac_storage_analyzer_get_model_metrics(
                    handle, regHandle, mid, framework.toCFramework(), &cMetrics
                )
            }

            guard result == RAC_SUCCESS else { return nil }

            return ModelStorageMetrics(
                modelID: cMetrics.model_id.map { String(cString: $0) } ?? modelId,
                sizeOnDiskBytes: cMetrics.size_on_disk
            )
        }

        /// Check if storage is available for a download
        /// Note: nonisolated because it only calls C functions and doesn't need actor state
        public nonisolated func checkStorageAvailable(
            modelSize: Int64,
            safetyMargin: Double = 0.1
        ) -> StorageAvailability {
            // Use C callbacks directly for synchronous check
            let available = storageGetAvailableSpaceCallback(userData: nil)
            let required = Int64(Double(modelSize) * (1.0 + safetyMargin))

            let isAvailable = available > required
            let hasWarning = available < required * 2

            let recommendation: String?
            if !isAvailable {
                let shortfall = required - available
                let formatter = ByteCountFormatter()
                formatter.countStyle = .memory
                recommendation = "Need \(formatter.string(fromByteCount: shortfall)) more space."
            } else if hasWarning {
                recommendation = "Storage space is getting low."
            } else {
                recommendation = nil
            }

            var availability = StorageAvailability.make(
                isAvailable: isAvailable,
                requiredBytes: required,
                availableBytes: available,
                recommendation: recommendation
            )
            if hasWarning {
                availability.warningMessage = recommendation ?? "Storage space is getting low."
            }
            return availability
        }

        /// Calculate size at a path
        public func calculateSize(at path: URL) throws -> Int64 {
            guard let handle = handle else {
                throw SDKException.general(.initializationFailed, "Storage analyzer not initialized")
            }

            var size: Int64 = 0
            let result = path.path.withCString { pathPtr in
                rac_storage_analyzer_calculate_size(handle, pathPtr, &size)
            }

            guard result == RAC_SUCCESS else {
                if result == RAC_ERROR_NOT_FOUND {
                    throw SDKException.fileManagement(.fileNotFound, "Path not found: \(path.path)")
                }
                throw SDKException.general(.processingFailed, "Failed to calculate size")
            }

            return size
        }

        public func info(_ request: RAStorageInfoRequest = RAStorageInfoRequest()) async -> RAStorageInfoResult {
            do {
                return try await invokeProto(
                    request,
                    symbol: StorageProtoABI.info,
                    responseType: RAStorageInfoResult.self
                )
            } catch {
                var result = RAStorageInfoResult()
                result.success = true
                result.info = await analyzeStorage()
                return result
            }
        }

        public func availability(
            _ request: RAStorageAvailabilityRequest
        ) async -> RAStorageAvailabilityResult {
            do {
                return try await invokeProto(
                    request,
                    symbol: StorageProtoABI.availability,
                    responseType: RAStorageAvailabilityResult.self
                )
            } catch {
                var result = RAStorageAvailabilityResult()
                result.success = true
                result.availability = checkStorageAvailable(
                    modelSize: request.requiredBytes,
                    safetyMargin: request.safetyMargin == 0 ? 0.1 : request.safetyMargin
                )
                result.warnings = [NativeProtoABI.unavailableMessage]
                return result
            }
        }

        public func deletePlan(
            _ request: RAStorageDeletePlanRequest
        ) async -> RAStorageDeletePlan {
            do {
                return try await invokeProto(
                    request,
                    symbol: StorageProtoABI.deletePlan,
                    responseType: RAStorageDeletePlan.self
                )
            } catch {
                return await fallbackDeletePlan(request)
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
                return await fallbackDelete(request)
            }
        }

        // MARK: - Private

        private func getRegistryHandle() async -> rac_model_registry_handle_t? {
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
                throw SDKException.general(.notSupported, NativeProtoABI.unavailableMessage)
            }
            guard let handle = handle, let registryHandle = await getRegistryHandle() else {
                throw SDKException.general(.initializationFailed, "Storage analyzer not initialized")
            }

            var outBuffer = rac_proto_buffer_t()
            defer { NativeProtoABI.free(&outBuffer) }

            let status = try NativeProtoABI.withSerializedBytes(request) { bytes, size in
                symbol(handle, registryHandle, bytes, size, &outBuffer)
            }
            guard status == RAC_SUCCESS else {
                throw SDKException.general(.processingFailed, "Storage proto request failed: \(status)")
            }
            return try NativeProtoABI.decode(responseType, from: outBuffer)
        }

        private func fallbackDeletePlan(_ request: RAStorageDeletePlanRequest) async -> RAStorageDeletePlan {
            let info = await analyzeStorage()
            let requestedIds = Set(request.modelIds)
            var plan = RAStorageDeletePlan()
            plan.requiredBytes = request.requiredBytes
            plan.warnings = [NativeProtoABI.unavailableMessage]

            for metrics in info.models where requestedIds.isEmpty || requestedIds.contains(metrics.modelID) {
                var candidate = RAStorageDeleteCandidate()
                candidate.modelID = metrics.modelID
                candidate.reclaimableBytes = metrics.sizeOnDiskBytes
                candidate.isLoaded = false
                plan.candidates.append(candidate)
                plan.reclaimableBytes += metrics.sizeOnDiskBytes
            }

            plan.canReclaimRequiredBytes = request.requiredBytes == 0 || plan.reclaimableBytes >= request.requiredBytes
            return plan
        }

        private func fallbackDelete(_ request: RAStorageDeleteRequest) async -> RAStorageDeleteResult {
            var result = RAStorageDeleteResult()
            result.warnings = [NativeProtoABI.unavailableMessage]

            let models = await CppBridge.ModelRegistry.shared.getAll()
            let requestedIds = Set(request.modelIds)
            let candidates = models.filter { model in
                !model.id.isEmpty && (requestedIds.isEmpty || requestedIds.contains(model.id))
            }

            for model in candidates {
                var deleted = false
                if request.deleteFiles, let path = model.localPath {
                    let size = (try? calculateSize(at: path)) ?? 0
                    if request.dryRun {
                        result.deletedBytes += size
                        result.deletedModelIds.append(model.id)
                        continue
                    }
                    do {
                        try Foundation.FileManager.default.removeItem(at: path)
                        result.deletedBytes += size
                        deleted = true
                    } catch {
                        result.failedModelIds.append(model.id)
                        continue
                    }
                }

                if request.clearRegistryPaths_p && !request.dryRun {
                    do {
                        try await CppBridge.ModelRegistry.shared.updateDownloadStatus(
                            modelId: model.id,
                            localPath: nil
                        )
                    } catch {
                        result.failedModelIds.append(model.id)
                        continue
                    }
                }

                if deleted || request.clearRegistryPaths_p || request.dryRun {
                    result.deletedModelIds.append(model.id)
                }
            }

            let requestedMissing = requestedIds.subtracting(Set(candidates.map(\.id)))
            result.failedModelIds.append(contentsOf: requestedMissing.sorted())
            result.success = result.failedModelIds.isEmpty
            if !result.success {
                result.errorMessage = "Some models could not be deleted"
            }
            return result
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

private func storageIsModelLoadedCallback(
    modelId _: UnsafePointer<CChar>?,
    outIsLoaded: UnsafeMutablePointer<rac_bool_t>?,
    userData _: UnsafeMutableRawPointer?
) -> rac_result_t {
    outIsLoaded?.pointee = RAC_FALSE
    return RAC_SUCCESS
}

private func storageUnloadModelCallback(
    modelId _: UnsafePointer<CChar>?,
    userData _: UnsafeMutableRawPointer?
) -> rac_result_t {
    return RAC_SUCCESS
}

// MARK: - Swift Type Conversions

extension StorageInfo {
    /// Initialize from C++ storage info
    init(from cInfo: rac_storage_info_t) {
        self.init()
        self.app = AppStorageInfo(
            documentsBytes: cInfo.app_storage.documents_size,
            cacheBytes: cInfo.app_storage.cache_size,
            appSupportBytes: cInfo.app_storage.app_support_size,
            totalBytes: cInfo.app_storage.total_size
        )
        self.device = DeviceStorageInfo(
            totalBytes: cInfo.device_storage.total_space,
            freeBytes: cInfo.device_storage.free_space,
            usedBytes: cInfo.device_storage.used_space
        )

        if let cModels = cInfo.models {
            for i in 0..<cInfo.model_count {
                let cMetrics = cModels[i]
                let metrics = ModelStorageMetrics(
                    modelID: cMetrics.model_id.map { String(cString: $0) } ?? "",
                    sizeOnDiskBytes: cMetrics.size_on_disk
                )
                self.models.append(metrics)
            }
        }

        self.totalModels = Int32(self.models.count)
        self.totalModelsBytes = self.models.reduce(0) { $0 + $1.sizeOnDiskBytes }
    }
}

// MARK: - ModelRegistry Handle Access

extension CppBridge.ModelRegistry {
    /// Get the underlying C handle (for use by other bridges)
    func getHandle() -> rac_model_registry_handle_t? {
        return handle
    }
}
