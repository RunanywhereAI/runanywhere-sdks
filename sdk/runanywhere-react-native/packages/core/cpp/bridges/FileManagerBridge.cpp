/**
 * @file FileManagerBridge.cpp
 * @brief C++ bridge for file manager operations.
 *
 * POSIX-based rac_file_callbacks_t implementation.
 * Works on both iOS and Android (both are POSIX-compliant).
 */

#include "FileManagerBridge.hpp"

#include <cstring>
#include <cstdlib>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <dirent.h>
#include <unistd.h>
#include <cerrno>

// Platform-specific logging
#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "FileManagerBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#include <cstdio>
#define LOGI(...) printf("[FileManagerBridge] "); printf(__VA_ARGS__); printf("\n")
#define LOGD(...) printf("[FileManagerBridge DEBUG] "); printf(__VA_ARGS__); printf("\n")
#define LOGE(...) printf("[FileManagerBridge ERROR] "); printf(__VA_ARGS__); printf("\n")
#endif

namespace runanywhere {
namespace bridges {

// =============================================================================
// POSIX Callback Implementations
// =============================================================================

static rac_result_t posixCreateDirectory(const char* path, int recursive, void* /*userData*/) {
    if (!path) return RAC_ERROR_NULL_POINTER;

    if (recursive) {
        // Create intermediate directories
        std::string pathStr(path);
        size_t pos = 0;
        while ((pos = pathStr.find('/', pos + 1)) != std::string::npos) {
            std::string subPath = pathStr.substr(0, pos);
            mkdir(subPath.c_str(), 0755);
        }
    }

    if (mkdir(path, 0755) == 0 || errno == EEXIST) {
        return RAC_SUCCESS;
    }
    return RAC_ERROR_FILE_IO;
}

static rac_result_t posixDeletePath(const char* path, int recursive, void* /*userData*/) {
    if (!path) return RAC_ERROR_NULL_POINTER;

    struct stat st;
    if (stat(path, &st) != 0) {
        return RAC_SUCCESS; // Already gone
    }

    if (S_ISDIR(st.st_mode)) {
        if (recursive) {
            // Recursively delete directory contents
            DIR* dir = opendir(path);
            if (!dir) return RAC_ERROR_FILE_IO;

            struct dirent* entry;
            while ((entry = readdir(dir)) != nullptr) {
                if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
                    continue;
                }
                std::string childPath = std::string(path) + "/" + entry->d_name;
                posixDeletePath(childPath.c_str(), 1, nullptr);
            }
            closedir(dir);
        }
        return (rmdir(path) == 0) ? RAC_SUCCESS : RAC_ERROR_FILE_IO;
    } else {
        return (unlink(path) == 0) ? RAC_SUCCESS : RAC_ERROR_FILE_IO;
    }
}

static rac_result_t posixListDirectory(const char* path, char*** outEntries,
                                        size_t* outCount, void* /*userData*/) {
    if (!path || !outEntries || !outCount) return RAC_ERROR_NULL_POINTER;

    *outEntries = nullptr;
    *outCount = 0;

    DIR* dir = opendir(path);
    if (!dir) return RAC_ERROR_FILE_NOT_FOUND;

    // First pass: count entries
    size_t count = 0;
    struct dirent* entry;
    while ((entry = readdir(dir)) != nullptr) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        count++;
    }

    if (count == 0) {
        closedir(dir);
        return RAC_SUCCESS;
    }

    // Allocate array
    char** entries = static_cast<char**>(malloc(count * sizeof(char*)));
    if (!entries) {
        closedir(dir);
        return RAC_ERROR_FILE_IO;
    }

    // Second pass: fill entries
    rewinddir(dir);
    size_t i = 0;
    while ((entry = readdir(dir)) != nullptr && i < count) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        entries[i] = strdup(entry->d_name);
        i++;
    }
    closedir(dir);

    *outEntries = entries;
    *outCount = i;
    return RAC_SUCCESS;
}

static void posixFreeEntries(char** entries, size_t count, void* /*userData*/) {
    if (!entries) return;
    for (size_t i = 0; i < count; i++) {
        free(entries[i]);
    }
    free(entries);
}

static rac_bool_t posixPathExists(const char* path, rac_bool_t* outIsDirectory,
                                   void* /*userData*/) {
    if (!path) return RAC_FALSE;

    struct stat st;
    if (stat(path, &st) != 0) return RAC_FALSE;

    if (outIsDirectory) {
        *outIsDirectory = S_ISDIR(st.st_mode) ? RAC_TRUE : RAC_FALSE;
    }
    return RAC_TRUE;
}

static int64_t posixGetFileSize(const char* path, void* /*userData*/) {
    if (!path) return -1;

    struct stat st;
    if (stat(path, &st) != 0) return -1;
    return static_cast<int64_t>(st.st_size);
}

static int64_t posixGetAvailableSpace(void* /*userData*/) {
    // Use root "/" on iOS, "/data" on Android
#if defined(ANDROID) || defined(__ANDROID__)
    const char* mountPoint = "/data";
#else
    const char* mountPoint = "/";
#endif

    struct statvfs vfs;
    if (statvfs(mountPoint, &vfs) != 0) return 0;
    return static_cast<int64_t>(vfs.f_bavail) * static_cast<int64_t>(vfs.f_frsize);
}

static int64_t posixGetTotalSpace(void* /*userData*/) {
#if defined(ANDROID) || defined(__ANDROID__)
    const char* mountPoint = "/data";
#else
    const char* mountPoint = "/";
#endif

    struct statvfs vfs;
    if (statvfs(mountPoint, &vfs) != 0) return 0;
    return static_cast<int64_t>(vfs.f_blocks) * static_cast<int64_t>(vfs.f_frsize);
}

// =============================================================================
// FileManagerBridge Implementation
// =============================================================================

FileManagerBridge& FileManagerBridge::shared() {
    static FileManagerBridge instance;
    return instance;
}

void FileManagerBridge::initialize() {
    if (isInitialized_) {
        LOGD("File manager bridge already initialized");
        return;
    }

    // Set up POSIX-based callbacks
    memset(&callbacks_, 0, sizeof(callbacks_));
    callbacks_.create_directory = posixCreateDirectory;
    callbacks_.delete_path = posixDeletePath;
    callbacks_.list_directory = posixListDirectory;
    callbacks_.free_entries = posixFreeEntries;
    callbacks_.path_exists = posixPathExists;
    callbacks_.get_file_size = posixGetFileSize;
    callbacks_.get_available_space = posixGetAvailableSpace;
    callbacks_.get_total_space = posixGetTotalSpace;
    callbacks_.user_data = nullptr;

    isInitialized_ = true;
    LOGI("File manager bridge initialized with POSIX callbacks");
}

void FileManagerBridge::shutdown() {
    isInitialized_ = false;
    memset(&callbacks_, 0, sizeof(callbacks_));
    LOGI("File manager bridge shutdown");
}

bool FileManagerBridge::createDirectoryStructure() {
    if (!isInitialized_) return false;
    return rac_file_manager_create_directory_structure(&callbacks_) == RAC_SUCCESS;
}

int64_t FileManagerBridge::calculateDirectorySize(const std::string& path) {
    if (!isInitialized_) return 0;

    int64_t size = 0;
    rac_result_t result = rac_file_manager_calculate_dir_size(&callbacks_, path.c_str(), &size);
    return (result == RAC_SUCCESS) ? size : 0;
}

int64_t FileManagerBridge::modelsStorageUsed() {
    if (!isInitialized_) return 0;

    int64_t size = 0;
    rac_result_t result = rac_file_manager_models_storage_used(&callbacks_, &size);
    return (result == RAC_SUCCESS) ? size : 0;
}

bool FileManagerBridge::clearCache() {
    if (!isInitialized_) return false;
    return rac_file_manager_clear_cache(&callbacks_) == RAC_SUCCESS;
}

bool FileManagerBridge::clearTemp() {
    if (!isInitialized_) return false;
    return rac_file_manager_clear_temp(&callbacks_) == RAC_SUCCESS;
}

int64_t FileManagerBridge::cacheSize() {
    if (!isInitialized_) return 0;

    int64_t size = 0;
    rac_result_t result = rac_file_manager_cache_size(&callbacks_, &size);
    return (result == RAC_SUCCESS) ? size : 0;
}

bool FileManagerBridge::deleteModel(const std::string& modelId, int framework) {
    if (!isInitialized_) return false;
    return rac_file_manager_delete_model(
        &callbacks_, modelId.c_str(),
        static_cast<rac_inference_framework_t>(framework)) == RAC_SUCCESS;
}

rac_file_manager_storage_info_t FileManagerBridge::getStorageInfo() {
    rac_file_manager_storage_info_t info = {};
    if (!isInitialized_) return info;

    rac_file_manager_get_storage_info(&callbacks_, &info);
    return info;
}

} // namespace bridges
} // namespace runanywhere
