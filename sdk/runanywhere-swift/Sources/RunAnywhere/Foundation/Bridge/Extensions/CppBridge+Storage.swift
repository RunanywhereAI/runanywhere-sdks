//
//  CppBridge+Storage.swift
//  RunAnywhere SDK
//
//  Storage analyzer bridge - C++ owns business logic, Swift provides file operations
//

import CRACommons
import Foundation

// MARK: - Storage Bridge

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

            // Get full ModelInfo from registry for complete data
            guard let modelInfo = await CppBridge.ModelRegistry.shared.get(modelId: modelId) else {
                return nil
            }

            return ModelStorageMetrics(model: modelInfo, sizeOnDisk: cMetrics.size_on_disk)
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

            return StorageAvailability(
                isAvailable: isAvailable,
                requiredSpace: required,
                availableSpace: available,
                hasWarning: hasWarning,
                recommendation: recommendation
            )
        }

        /// Calculate size at a path
        public func calculateSize(at path: URL) throws -> Int64 {
            guard let handle = handle else {
                throw SDKError.general(.initializationFailed, "Storage analyzer not initialized")
            }

            var size: Int64 = 0
            let result = path.path.withCString { pathPtr in
                rac_storage_analyzer_calculate_size(handle, pathPtr, &size)
            }

            guard result == RAC_SUCCESS else {
                if result == RAC_ERROR_NOT_FOUND {
                    throw SDKError.fileManagement(.fileNotFound, "Path not found: \(path.path)")
                }
                throw SDKError.general(.processingFailed, "Failed to calculate size")
            }

            return size
        }

        // MARK: - Private

        private func getRegistryHandle() async -> rac_model_registry_handle_t? {
            // Access the registry's handle
            // Note: We need to expose this from CppBridge.ModelRegistry
            return await CppBridge.ModelRegistry.shared.getHandle()
        }
    }
}

// MARK: - C Callbacks (Platform-Specific File Operations)

/// Calculate directory size using FileManager
private func storageCalculateDirSizeCallback(
    path: UnsafePointer<CChar>?,
    userData _: UnsafeMutableRawPointer?
) -> Int64 {
    guard let path = path else { return 0 }
    let url = URL(fileURLWithPath: String(cString: path))
    return calculateDirectorySize(at: url)
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

/// Calculate directory size (recursive)
private func calculateDirectorySize(at url: URL) -> Int64 {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(
        at: url,
        includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        // Maybe it's a file, not a directory
        return FileOperationsUtilities.fileSize(at: url) ?? 0
    }

    var totalSize: Int64 = 0
    for case let fileURL as URL in enumerator {
        if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
           values.isRegularFile == true {
            totalSize += Int64(values.fileSize ?? 0)
        }
    }
    return totalSize
}

// MARK: - Swift Type Conversions

extension StorageInfo {
    /// Initialize from C++ storage info
    init(from cInfo: rac_storage_info_t) {
        // Convert app storage
        let appStorage = AppStorageInfo(
            documentsSize: cInfo.app_storage.documents_size,
            cacheSize: cInfo.app_storage.cache_size,
            appSupportSize: cInfo.app_storage.app_support_size,
            totalSize: cInfo.app_storage.total_size
        )

        // Convert device storage
        let deviceStorage = DeviceStorageInfo(
            totalSpace: cInfo.device_storage.total_space,
            freeSpace: cInfo.device_storage.free_space,
            usedSpace: cInfo.device_storage.used_space
        )

        // Convert model metrics - need to get full ModelInfo from registry
        var models: [ModelStorageMetrics] = []
        if let cModels = cInfo.models {
            for i in 0..<cInfo.model_count {
                let cMetrics = cModels[i]
                // Create minimal ModelInfo from C++ data
                let modelInfo = ModelInfo(
                    id: cMetrics.model_id.map { String(cString: $0) } ?? "",
                    name: cMetrics.model_name.map { String(cString: $0) } ?? "",
                    category: .language,  // Will be enriched if needed
                    format: ModelFormat(from: cMetrics.format),
                    framework: InferenceFramework(from: cMetrics.framework),
                    localPath: cMetrics.local_path.map { URL(fileURLWithPath: String(cString: $0)) }
                )
                models.append(ModelStorageMetrics(model: modelInfo, sizeOnDisk: cMetrics.size_on_disk))
            }
        }

        self.init(appStorage: appStorage, deviceStorage: deviceStorage, models: models)
    }
}

// MARK: - ModelRegistry Handle Access

extension CppBridge.ModelRegistry {
    /// Get the underlying C handle (for use by other bridges)
    func getHandle() -> rac_model_registry_handle_t? {
        return handle
    }
}
