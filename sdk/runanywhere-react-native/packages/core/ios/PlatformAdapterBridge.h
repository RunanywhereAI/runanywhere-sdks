/**
 * PlatformAdapterBridge.h
 *
 * C interface for platform-specific operations (Keychain, File I/O).
 * Called from C++ via extern "C" functions.
 */

#ifndef PlatformAdapterBridge_h
#define PlatformAdapterBridge_h

#include <stdbool.h>

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
// HTTP POST for Device Registration (Synchronous)
// ============================================================================

/**
 * Synchronous HTTP POST for device registration
 * Called from C++ device manager callbacks
 *
 * @param url Full URL to POST to
 * @param jsonBody JSON body string
 * @param supabaseKey Supabase API key (for dev mode, can be NULL)
 * @param outStatusCode Pointer to store HTTP status code
 * @param outResponseBody Pointer to store response body (must be freed by caller)
 * @param outErrorMessage Pointer to store error message (must be freed by caller)
 * @return true if request succeeded (2xx or 409)
 */
bool PlatformAdapter_httpPostSync(
    const char* url,
    const char* jsonBody,
    const char* supabaseKey,
    int* outStatusCode,
    char** outResponseBody,
    char** outErrorMessage
);

#ifdef __cplusplus
}
#endif

#endif /* PlatformAdapterBridge_h */

