/**
 * PlatformAdapterBridge.h
 *
 * C interface for platform-specific operations (Keychain, File I/O).
 * Called from C++ via extern "C" functions.
 */

#ifndef PlatformAdapterBridge_h
#define PlatformAdapterBridge_h

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// Secure Storage (Keychain)
// ============================================================================

/**
 * Set a value in the Keychain
 * @param key The key to store under
 * @param value The value to store
 * @return true if successful
 */
bool PlatformAdapter_secureSet(const char* key, const char* value);

/**
 * Get a value from the Keychain
 * @param key The key to retrieve
 * @param outValue Pointer to store the result (must be freed by caller with free())
 * @return true if found
 */
bool PlatformAdapter_secureGet(const char* key, char** outValue);

/**
 * Delete a value from the Keychain
 * @param key The key to delete
 * @return true if successful
 */
bool PlatformAdapter_secureDelete(const char* key);

/**
 * Check if a key exists in the Keychain
 * @param key The key to check
 * @return true if exists
 */
bool PlatformAdapter_secureExists(const char* key);

/**
 * Get persistent device UUID (from Keychain or generate new)
 * @param outValue Pointer to store the UUID (must be freed by caller with free())
 * @return true if successful
 */
bool PlatformAdapter_getPersistentDeviceUUID(char** outValue);

// ============================================================================
// Native Directories
// ============================================================================

/**
 * Get the native model base directory.
 * iOS returns the app Documents directory.
 * @param outValue Pointer to store the result (must be freed by caller with free())
 * @return true if successful
 */
bool PlatformAdapter_getModelBaseDirectory(char** outValue);

// ============================================================================
// Device Info (Synchronous)
// ============================================================================

/**
 * Get device model name (e.g., "iPhone 16 Pro Max")
 * @param outValue Pointer to store the result (must be freed by caller)
 * @return true if successful
 */
bool PlatformAdapter_getDeviceModel(char** outValue);

/**
 * Get OS version (e.g., "18.2")
 * @param outValue Pointer to store the result (must be freed by caller)
 * @return true if successful
 */
bool PlatformAdapter_getOSVersion(char** outValue);

/**
 * Get chip name (e.g., "A18 Pro")
 * @param outValue Pointer to store the result (must be freed by caller)
 * @return true if successful
 */
bool PlatformAdapter_getChipName(char** outValue);

/**
 * Get total memory in bytes
 * @return Total memory in bytes
 */
uint64_t PlatformAdapter_getTotalMemory(void);

/**
 * Get available memory in bytes
 * @return Available memory in bytes
 */
uint64_t PlatformAdapter_getAvailableMemory(void);

/**
 * Get CPU core count
 * @return Number of CPU cores
 */
int PlatformAdapter_getCoreCount(void);

/**
 * Get architecture (e.g., "arm64")
 * @param outValue Pointer to store the result (must be freed by caller)
 * @return true if successful
 */
bool PlatformAdapter_getArchitecture(char** outValue);

/**
 * Get GPU family (e.g., "apple" for iOS, "mali", "adreno" for Android)
 * @param outValue Pointer to store the result (must be freed by caller)
 * @return true if successful
 */
bool PlatformAdapter_getGPUFamily(char** outValue);

/**
 * Check if device is a tablet
 * Uses UIDevice.userInterfaceIdiom on iOS, Configuration on Android
 * @return true if device is a tablet
 */
bool PlatformAdapter_isTablet(void);

// ============================================================================
// App / Client Info
// ============================================================================

bool PlatformAdapter_getAppIdentifier(char** outValue);
bool PlatformAdapter_getAppName(char** outValue);
bool PlatformAdapter_getAppVersion(char** outValue);
bool PlatformAdapter_getAppBuild(char** outValue);
bool PlatformAdapter_getLocaleIdentifier(char** outValue);
bool PlatformAdapter_getTimezoneIdentifier(char** outValue);

// ============================================================================
// HTTP Download (Async Platform Adapter Fallback)
// ============================================================================

/**
 * Start an HTTP download for RACommons platform-adapter-only callers.
 * Public RN model downloads use native C++ rac_http_download_execute.
 * @param url URL to download
 * @param destinationPath Destination file path
 * @param taskId Task identifier (provided by C++)
 * @return RAC_SUCCESS on success, error code otherwise
 */
int PlatformAdapter_httpDownload(
    const char* url,
    const char* destinationPath,
    const char* taskId
);

/**
 * Cancel an HTTP download.
 * @param taskId Task identifier
 * @return true if cancellation initiated
 */
bool PlatformAdapter_httpDownloadCancel(const char* taskId);

// ============================================================================
// Directory Enumeration (Platform Adapter Slots)
// ============================================================================

#include <stddef.h>

/**
 * One directory entry surface for the C++ platform adapter
 * file_list_directory slot. Mirrors `rac_directory_entry_t` field-for-field
 * so the C++ side can memcpy into the caller-provided rac_directory_entry_t
 * array without an additional marshalling layer.
 */
typedef struct PlatformDirectoryEntry {
    char name[512];  // RAC_DIRECTORY_ENTRY_NAME_MAX
    bool is_dir;
    int64_t size_bytes;
} PlatformDirectoryEntry;

/**
 * Enumerate directory entries via FileManager.contentsOfDirectory.
 *
 * Two-call semantics: pass outEntries == NULL to query required capacity,
 * then allocate and call again. Mirrors the rac_file_list_directory_fn
 * contract documented on rac_platform_adapter.h.
 *
 * Truncation: entries whose UTF-8 name (+NUL) would exceed 512 bytes are
 * skipped per the rac_directory_entry_t::name contract.
 *
 * @param dirPath     Absolute directory path.
 * @param outEntries  Caller-allocated array (or NULL for capacity query).
 * @param inOutCount  In: capacity of outEntries; Out: entries written
 *                    (or total available when outEntries is NULL).
 * @param outResult   Output result code (0=success, -183=not found,
 *                    -805=internal error). MUST be non-NULL.
 */
void PlatformAdapter_listDirectory(const char* dirPath,
                                   PlatformDirectoryEntry* outEntries,
                                   size_t* inOutCount,
                                   int* outResult);

/**
 * Check whether a path is a directory containing at least one entry.
 *
 * Used by rac_model_info_make_proto's is_downloaded gating for multi-file
 * artifacts (mmproj + GGUF pairs, tokenizer + ONNX bundles).
 *
 * @param path Absolute directory path.
 * @return true if the path is a directory with at least one entry; false
 *         otherwise (missing, empty, or a regular file).
 */
bool PlatformAdapter_isNonEmptyDirectory(const char* path);

/**
 * Apple-only: returns UIDevice.identifierForVendor.uuidString.
 *
 * Used by rac_device_get_or_create_persistent_id as the stable fallback
 * when secure-storage cache misses. Buffer must be >= 37 bytes.
 *
 * @param outBuffer  Caller-provided buffer to receive the UUID string.
 * @param bufferSize Buffer size in bytes; MUST be >= 37 to succeed.
 * @return 0 on success (outBuffer NUL-terminated), -423 if no vendor id
 *         available, -261 if bufferSize is too small.
 */
int PlatformAdapter_getVendorId(char* outBuffer, size_t bufferSize);

#ifdef __cplusplus
}
#endif

#endif /* PlatformAdapterBridge_h */
