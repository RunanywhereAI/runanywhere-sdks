//
//  CppBridge+FileManager.swift
//  RunAnywhere SDK
//
//  File manager bridge - C++ owns business logic, Swift provides file I/O callbacks.
//  Consolidates duplicated file management logic from SimplifiedFileManager.
//

import CRACommons
import Foundation

// MARK: - File Manager Bridge

extension CppBridge {

    /// File manager bridge to C++ rac_file_manager
    /// C++ handles: recursive dir size, directory structure, cache clearing, storage checks
    /// Swift provides: thin I/O callbacks (create dir, delete, list, stat, file size)
    public enum FileManager {

        private static let logger = SDKLogger(category: "CppBridge.FileManager")

        // MARK: - Callbacks Construction

        /// Build rac_file_callbacks_t with Swift I/O implementations
        static func makeCallbacks() -> rac_file_callbacks_t {
            var cb = rac_file_callbacks_t()
            cb.create_directory = fmCreateDirectoryCallback
            cb.delete_path = fmDeletePathCallback
            cb.list_directory = fmListDirectoryCallback
            cb.free_entries = fmFreeEntriesCallback
            cb.path_exists = fmPathExistsCallback
            cb.get_file_size = fmGetFileSizeCallback
            cb.get_available_space = fmGetAvailableSpaceCallback
            cb.get_total_space = fmGetTotalSpaceCallback
            cb.user_data = nil
            return cb
        }

        // MARK: - Public API

        /// Create directory structure (Models, Cache, Temp, Downloads)
        public static func createDirectoryStructure() -> Bool {
            var cb = makeCallbacks()
            let result = rac_file_manager_create_directory_structure(&cb)
            return result == RAC_SUCCESS
        }

        /// Calculate directory size recursively (C++ logic, Swift I/O)
        public static func calculateDirectorySize(at url: URL) -> Int64 {
            var cb = makeCallbacks()
            var size: Int64 = 0
            url.path.withCString { pathPtr in
                _ = rac_file_manager_calculate_dir_size(&cb, pathPtr, &size)
            }
            return size
        }

        /// Get total models storage used
        public static func modelsStorageUsed() -> Int64 {
            var cb = makeCallbacks()
            var size: Int64 = 0
            _ = rac_file_manager_models_storage_used(&cb, &size)
            return size
        }

        /// Clear cache directory
        public static func clearCache() -> Bool {
            var cb = makeCallbacks()
            return rac_file_manager_clear_cache(&cb) == RAC_SUCCESS
        }

        /// Clear temp directory
        public static func clearTemp() -> Bool {
            var cb = makeCallbacks()
            return rac_file_manager_clear_temp(&cb) == RAC_SUCCESS
        }

        /// Get cache size
        public static func cacheSize() -> Int64 {
            var cb = makeCallbacks()
            var size: Int64 = 0
            _ = rac_file_manager_cache_size(&cb, &size)
            return size
        }

        /// Delete a model folder
        public static func deleteModel(modelId: String, framework: InferenceFramework) -> Bool {
            var cb = makeCallbacks()
            return modelId.withCString { mid in
                rac_file_manager_delete_model(&cb, mid, framework.toCFramework()) == RAC_SUCCESS
            }
        }

        /// Check if model folder exists
        public static func modelFolderExists(modelId: String, framework: InferenceFramework) -> Bool {
            var cb = makeCallbacks()
            var exists: rac_bool_t = RAC_FALSE
            modelId.withCString { mid in
                _ = rac_file_manager_model_folder_exists(&cb, mid, framework.toCFramework(), &exists, nil)
            }
            return exists == RAC_TRUE
        }

        /// Check if model folder exists and has contents
        public static func modelFolderHasContents(modelId: String, framework: InferenceFramework) -> Bool {
            var cb = makeCallbacks()
            var exists: rac_bool_t = RAC_FALSE
            var hasContents: rac_bool_t = RAC_FALSE
            modelId.withCString { mid in
                _ = rac_file_manager_model_folder_exists(&cb, mid, framework.toCFramework(), &exists, &hasContents)
            }
            return exists == RAC_TRUE && hasContents == RAC_TRUE
        }

        /// Get combined storage info
        public static func getStorageInfo() -> rac_file_manager_storage_info_t {
            var cb = makeCallbacks()
            var info = rac_file_manager_storage_info_t()
            _ = rac_file_manager_get_storage_info(&cb, &info)
            return info
        }

        /// Check storage availability
        public static func checkStorage(requiredBytes: Int64) -> rac_storage_availability_t {
            var cb = makeCallbacks()
            var availability = rac_storage_availability_t()
            _ = rac_file_manager_check_storage(&cb, requiredBytes, &availability)
            return availability
        }
    }
}

// MARK: - C Callbacks (Platform-Specific I/O)

/// Create a directory, optionally with intermediate directories
private func fmCreateDirectoryCallback(
    path: UnsafePointer<CChar>?,
    recursive: Int32,
    userData _: UnsafeMutableRawPointer?
) -> rac_result_t {
    guard let path = path else { return RAC_ERROR_NULL_POINTER }
    let url = URL(fileURLWithPath: String(cString: path))
    do {
        try Foundation.FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: recursive != 0,
            attributes: nil
        )
        return RAC_SUCCESS
    } catch {
        return RAC_ERROR_DIRECTORY_CREATION_FAILED
    }
}

/// Delete a file or directory
private func fmDeletePathCallback(
    path: UnsafePointer<CChar>?,
    recursive _: Int32,
    userData _: UnsafeMutableRawPointer?
) -> rac_result_t {
    guard let path = path else { return RAC_ERROR_NULL_POINTER }
    let pathStr = String(cString: path)
    do {
        if Foundation.FileManager.default.fileExists(atPath: pathStr) {
            try Foundation.FileManager.default.removeItem(atPath: pathStr)
        }
        return RAC_SUCCESS
    } catch {
        return RAC_ERROR_DELETE_FAILED
    }
}

/// List directory contents (entry names only)
private func fmListDirectoryCallback(
    path: UnsafePointer<CChar>?,
    outEntries: UnsafeMutablePointer<UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?>?,
    outCount: UnsafeMutablePointer<Int>?,
    userData _: UnsafeMutableRawPointer?
) -> rac_result_t {
    guard let path = path, let outEntries = outEntries, let outCount = outCount else {
        return RAC_ERROR_NULL_POINTER
    }

    let pathStr = String(cString: path)
    guard let contents = try? Foundation.FileManager.default.contentsOfDirectory(atPath: pathStr) else {
        outEntries.pointee = nil
        outCount.pointee = 0
        return RAC_ERROR_FILE_NOT_FOUND
    }

    let count = contents.count
    let entries = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: count)

    for (i, name) in contents.enumerated() {
        entries[i] = strdup(name)
    }

    outEntries.pointee = entries
    outCount.pointee = count
    return RAC_SUCCESS
}

/// Free directory entries
private func fmFreeEntriesCallback(
    entries: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
    count: Int,
    userData _: UnsafeMutableRawPointer?
) {
    guard let entries = entries else { return }
    for i in 0..<count {
        if let entry = entries[i] {
            free(entry)
        }
    }
    entries.deallocate()
}

/// Check if path exists and whether it's a directory
private func fmPathExistsCallback(
    path: UnsafePointer<CChar>?,
    outIsDirectory: UnsafeMutablePointer<rac_bool_t>?,
    userData _: UnsafeMutableRawPointer?
) -> rac_bool_t {
    guard let path = path else { return RAC_FALSE }
    let pathStr = String(cString: path)
    var isDir: ObjCBool = false
    let exists = Foundation.FileManager.default.fileExists(atPath: pathStr, isDirectory: &isDir)
    outIsDirectory?.pointee = isDir.boolValue ? RAC_TRUE : RAC_FALSE
    return exists ? RAC_TRUE : RAC_FALSE
}

/// Get file size
private func fmGetFileSizeCallback(
    path: UnsafePointer<CChar>?,
    userData _: UnsafeMutableRawPointer?
) -> Int64 {
    guard let path = path else { return -1 }
    let pathStr = String(cString: path)
    guard let attrs = try? Foundation.FileManager.default.attributesOfItem(atPath: pathStr),
          let size = attrs[.size] as? Int64 else {
        return -1
    }
    return size
}

/// Get available disk space
private func fmGetAvailableSpaceCallback(userData _: UnsafeMutableRawPointer?) -> Int64 {
    do {
        let attrs = try Foundation.FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        return (attrs[.systemFreeSize] as? Int64) ?? 0
    } catch {
        return 0
    }
}

/// Get total disk space
private func fmGetTotalSpaceCallback(userData _: UnsafeMutableRawPointer?) -> Int64 {
    do {
        let attrs = try Foundation.FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        return (attrs[.systemSize] as? Int64) ?? 0
    } catch {
        return 0
    }
}
