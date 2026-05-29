/**
 * @file rac_platform_adapter.h
 * @brief RunAnywhere Commons - Platform Adapter Interface
 *
 * Platform adapter provides callbacks for platform-specific operations.
 * Swift/Kotlin SDK implements these callbacks and passes them during init.
 *
 * NOTE: HTTP networking is delegated to the platform layer (Swift/Kotlin).
 * The C++ layer only handles orchestration logic.
 *
 * Threading contract:
 *   Adapter callbacks may be invoked from any thread (download workers,
 *   voice-agent pipeline, LLM streaming, model-registry refresh, etc.).
 *   All callbacks MUST be thread-safe and re-entrant unless an individual
 *   slot's doc-block explicitly documents otherwise. Implementations that
 *   guard shared state (keychain, file handles, log sinks) are responsible
 *   for their own synchronization — commons does not serialize calls.
 */

#ifndef RAC_PLATFORM_ADAPTER_H
#define RAC_PLATFORM_ADAPTER_H

#include "rac_error.h"
#include "rac_types.h"
#include "rac_model_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// CALLBACK TYPES (defined outside struct for C compatibility)
// =============================================================================

/**
 * HTTP download progress callback type.
 * @param bytes_downloaded Bytes downloaded so far
 * @param total_bytes Total bytes to download (0 if unknown)
 * @param callback_user_data Context passed to http_download
 */
typedef void (*rac_http_progress_callback_fn)(int64_t bytes_downloaded, int64_t total_bytes,
                                              void* callback_user_data);

/**
 * HTTP download completion callback type.
 * @param result RAC_SUCCESS or error code
 * @param downloaded_path Path to downloaded file (NULL on failure)
 * @param callback_user_data Context passed to http_download
 */
typedef void (*rac_http_complete_callback_fn)(rac_result_t result, const char* downloaded_path,
                                              void* callback_user_data);

/**
 * Archive extraction progress callback type.
 * @param files_extracted Number of files extracted so far
 * @param total_files Total files to extract
 * @param callback_user_data Context passed to extract_archive
 */
typedef void (*rac_extract_progress_callback_fn)(int32_t files_extracted, int32_t total_files,
                                                 void* callback_user_data);

// =============================================================================
// DIRECTORY LISTING (for model registry rescan)
// =============================================================================

/**
 * Maximum length (including null terminator) of a directory entry name written
 * by the file_list_directory callback. Mirrors POSIX `NAME_MAX`-class sizing
 * so platform implementations can stack-allocate fixed buffers.
 */
#define RAC_DIRECTORY_ENTRY_NAME_MAX 512

/**
 * One entry produced by `rac_platform_adapter_t::file_list_directory`.
 *
 * The struct is plain-old-data so the platform adapter (Swift/Kotlin/Dart/JS)
 * can fill caller-provided arrays without managing additional ownership.
 */
typedef struct rac_directory_entry {
    /** Entry name (no path component). UTF-8, null-terminated.
     *
     * Truncation contract: when the underlying filesystem produces an entry
     * name whose byte length (including NUL) would exceed
     * `RAC_DIRECTORY_ENTRY_NAME_MAX`, the platform implementation MUST skip
     * that entry rather than silently truncate it, and SHOULD emit a
     * RAC_LOG_WARN log via the adapter's `log` slot (category
     * "PlatformAdapter") so operators can detect oversized names. This keeps
     * the canonical RunAnywhere model-registry path layout safe — model IDs
     * never approach 511 bytes in practice — while ensuring the no-error
     * path cannot return a half-name that aliases a different artifact. */
    char name[RAC_DIRECTORY_ENTRY_NAME_MAX];
    /** RAC_TRUE if the entry is a directory, RAC_FALSE for regular files. */
    rac_bool_t is_dir;
    /** File size in bytes (0 for directories or unknown). */
    int64_t size_bytes;
} rac_directory_entry_t;

/**
 * List directory contents into a caller-provided array.
 *
 * Two-call semantics mirroring POSIX `getdents`/Win32 `FindFirstFile`:
 *
 *   1. Caller passes `out_entries == NULL` to query required capacity. The
 *      callback writes the total entry count into *in_out_count and returns
 *      RAC_SUCCESS without touching the entries array.
 *   2. Caller allocates an array of at least *in_out_count entries, calls
 *      again with `out_entries` non-NULL. The callback fills up to
 *      *in_out_count entries and updates *in_out_count to the number actually
 *      written.
 *
 * Hidden entries ("." / ".." / dotfiles) MAY be filtered by the implementation;
 * the C++ rescan code does not require them.
 *
 * @param dir_path     Absolute directory path to enumerate.
 * @param out_entries  Caller-allocated array (or NULL for capacity query).
 * @param in_out_count In: capacity of out_entries; Out: entries written
 *                     (or total available when out_entries is NULL).
 * @param user_data    Platform context.
 * @return RAC_SUCCESS, RAC_ERROR_FILE_NOT_FOUND when dir_path doesn't exist,
 *         or another error code on failure.
 */
typedef rac_result_t (*rac_file_list_directory_fn)(const char* dir_path,
                                                   rac_directory_entry_t* out_entries,
                                                   size_t* in_out_count, void* user_data);

// =============================================================================
// PLATFORM ADAPTER STRUCTURE
// =============================================================================

/**
 * Platform adapter structure.
 *
 * Implements platform-specific operations via callbacks.
 * The SDK layer (Swift/Kotlin) provides these implementations.
 *
 * ABI-evolution contract (NORMATIVE):
 *   This struct is a positional ABI contract shared between commons and every
 *   SDK's pinned header copy (XCFramework / .so / WASM offset table). Unlike the
 *   plugin vtable (`rac_engine_vtable_t`, which carries an `abi_version` that
 *   commons rejects on mismatch), this struct has NO version/size field today,
 *   so commons CANNOT detect a consumer that pins an older SDK while linking a
 *   newer commons. The slot-by-slot NULL-check pattern (every call site guards
 *   its slot before invoking it) is the only safety net: a divergent layout
 *   typically surfaces as a NULL/garbage slot that fails its own guard rather
 *   than silent state corruption. Therefore, when EXTENDING this struct, new
 *   callback slots MUST be appended immediately before `user_data` (never
 *   inserted earlier) and MUST be Optional / NULL-safe at their call site, so an
 *   older SDK that zero-inits or omits the new tail slot still initialises
 *   safely. A future hardening pass may prepend `uint32_t abi_version` +
 *   `uint32_t struct_size`, but that is an ABI break requiring a synchronized
 *   rollout across all five SDK populators (Swift/Kotlin-JNI/RN/Flutter/Web)
 *   plus every pinned binary header and the WASM offset table, and is therefore
 *   intentionally NOT done here.
 */
typedef struct rac_platform_adapter {
    // -------------------------------------------------------------------------
    // File System Operations
    // -------------------------------------------------------------------------

    /**
     * Check if a file exists.
     * @param path File path
     * @param user_data Platform context
     * @return RAC_TRUE if file exists, RAC_FALSE otherwise
     */
    rac_bool_t (*file_exists)(const char* path, void* user_data);

    /**
     * Read file contents.
     * @param path File path
     * @param out_data Output buffer (caller must free with rac_free)
     * @param out_size Output file size
     * @param user_data Platform context
     * @return RAC_SUCCESS on success, error code on failure
     */
    rac_result_t (*file_read)(const char* path, void** out_data, size_t* out_size, void* user_data);

    /**
     * Write file contents.
     * @param path File path
     * @param data Data to write
     * @param size Data size
     * @param user_data Platform context
     * @return RAC_SUCCESS on success, error code on failure
     */
    rac_result_t (*file_write)(const char* path, const void* data, size_t size, void* user_data);

    /**
     * Delete a file.
     * @param path File path
     * @param user_data Platform context
     * @return RAC_SUCCESS on success, error code on failure
     */
    rac_result_t (*file_delete)(const char* path, void* user_data);

    // -------------------------------------------------------------------------
    // Secure Storage (Keychain/KeyStore)
    // -------------------------------------------------------------------------

    /**
     * Get a value from secure storage.
     *
     * Not-found vs error contract (normative):
     *   - On a clean "key does not exist" miss the implementation MUST return
     *     RAC_ERROR_FILE_NOT_FOUND and MUST NOT set *out_value. Commons
     *     consumers (e.g. rac_device_get_or_create_persistent_id) use this
     *     specific code to distinguish a benign miss from a real keychain
     *     failure and decide whether to fall back vs propagate.
     *   - On any real failure (keychain locked, permission denied, decoding
     *     error, etc.) the implementation MUST return
     *     RAC_ERROR_SECURE_STORAGE_FAILED (or another non-RAC_SUCCESS,
     *     non-RAC_ERROR_FILE_NOT_FOUND code).
     *   - Returning RAC_ERROR_NOT_FOUND, RAC_ERROR_SECURE_STORAGE_FAILED, or
     *     any other code for the not-found case is a contract violation —
     *     commons will conservatively treat all non-RAC_SUCCESS results as
     *     "miss" today, but future consumers may rely on the discrimination.
     *
     * @param key Key name
     * @param out_value Output value (caller must free with rac_free); only
     *                  written on RAC_SUCCESS
     * @param user_data Platform context
     * @return RAC_SUCCESS on success, RAC_ERROR_FILE_NOT_FOUND if not found,
     *         RAC_ERROR_SECURE_STORAGE_FAILED (or other) on real errors
     */
    rac_result_t (*secure_get)(const char* key, char** out_value, void* user_data);

    /**
     * Set a value in secure storage.
     * @param key Key name
     * @param value Value to store
     * @param user_data Platform context
     * @return RAC_SUCCESS on success, error code on failure
     */
    rac_result_t (*secure_set)(const char* key, const char* value, void* user_data);

    /**
     * Delete a value from secure storage.
     * @param key Key name
     * @param user_data Platform context
     * @return RAC_SUCCESS on success, error code on failure
     */
    rac_result_t (*secure_delete)(const char* key, void* user_data);

    // -------------------------------------------------------------------------
    // Logging
    // -------------------------------------------------------------------------

    /**
     * Log a message.
     * @param level Log level
     * @param category Log category (e.g., "ModuleRegistry")
     * @param message Log message
     * @param user_data Platform context
     */
    void (*log)(rac_log_level_t level, const char* category, const char* message, void* user_data);

    // -------------------------------------------------------------------------
    // Error Tracking (Optional - for Sentry/crash reporting)
    // -------------------------------------------------------------------------

    /**
     * Track a structured error for telemetry/crash reporting.
     * Can be NULL - errors will still be logged but not sent to Sentry.
     *
     * Called for non-expected errors (i.e., not cancellations).
     * The JSON string contains full error details including stack trace.
     *
     * @param error_json JSON representation of the structured error
     * @param user_data Platform context
     */
    void (*track_error)(const char* error_json, void* user_data);

    // -------------------------------------------------------------------------
    // Clock
    // -------------------------------------------------------------------------

    /**
     * Get current time in milliseconds since Unix epoch.
     * @param user_data Platform context
     * @return Current time in milliseconds
     */
    int64_t (*now_ms)(void* user_data);

    // -------------------------------------------------------------------------
    // Memory Info
    // -------------------------------------------------------------------------

    /**
     * Get memory information.
     * @param out_info Output memory info structure
     * @param user_data Platform context
     * @return RAC_SUCCESS on success, error code on failure
     */
    rac_result_t (*get_memory_info)(rac_memory_info_t* out_info, void* user_data);

    // -------------------------------------------------------------------------
    // HTTP Download (Optional - can be NULL)
    // -------------------------------------------------------------------------

    /**
     * Start an HTTP download.
     * Can be NULL - download orchestration in C++ will call back to Swift/Kotlin.
     *
     * @param url URL to download from
     * @param destination_path Where to save the downloaded file
     * @param progress_callback Progress callback (can be NULL)
     * @param complete_callback Completion callback
     * @param callback_user_data User context for callbacks
     * @param out_task_id Output: Task ID for cancellation (owned, must be freed)
     * @param user_data Platform context
     * @return RAC_SUCCESS if download started, error code otherwise
     */
    rac_result_t (*http_download)(const char* url, const char* destination_path,
                                  rac_http_progress_callback_fn progress_callback,
                                  rac_http_complete_callback_fn complete_callback,
                                  void* callback_user_data, char** out_task_id, void* user_data);

    /**
     * Cancel an HTTP download.
     * Can be NULL.
     *
     * @param task_id Task ID returned from http_download
     * @param user_data Platform context
     * @return RAC_SUCCESS if cancelled, error code otherwise
     */
    rac_result_t (*http_download_cancel)(const char* task_id, void* user_data);

    // -------------------------------------------------------------------------
    // Archive Extraction (Optional - can be NULL)
    // -------------------------------------------------------------------------

    /**
     * Extract an archive (ZIP or TAR).
     * Can be NULL - extraction will be handled by Swift/Kotlin.
     *
     * @param archive_path Path to the archive
     * @param destination_dir Where to extract files
     * @param progress_callback Progress callback (can be NULL)
     * @param callback_user_data User context for callback
     * @param user_data Platform context
     * @return RAC_SUCCESS if extracted, error code otherwise
     */
    rac_result_t (*extract_archive)(const char* archive_path, const char* destination_dir,
                                    rac_extract_progress_callback_fn progress_callback,
                                    void* callback_user_data, void* user_data);

    // -------------------------------------------------------------------------
    // Directory Enumeration (Optional - can be NULL)
    // -------------------------------------------------------------------------

    /**
     * Enumerate the entries in a directory.
     *
     * Optional. When non-NULL, the C++ model registry refresh path can rescan
     * on-disk model folders without the SDK having to wire up the legacy
     * `rac_discovery_callbacks_t` struct. When NULL the rescan path falls
     * back to a no-op + a structured warning string in
     * `ModelRegistryRefreshResult.warnings` ("rescan_local requires platform
     * filesystem callbacks in the C ABI refresh path"), preserving prior
     * behaviour.
     *
     * Two-call semantics: pass NULL `out_entries` to query capacity, then
     * allocate and call again. See `rac_file_list_directory_fn` docs.
     *
     * Cross-SDK status (each SDK is responsible for populating this slot on
     * every platform whose runtime exposes a directory enumeration API):
     *   - Web:           POPULATED (registerFileListDirectory in
     *                    PlatformAdapter.ts via OPFS).
     *   - Swift (iOS):   SHOULD be populated via FileManager.contentsOfDirectory
     *                    (currently NULL — refresh emits the warning above).
     *   - Kotlin / RN Android: SHOULD be populated via java.io.File.listFiles().
     *   - Flutter:       SHOULD be populated via Dart FFI trampoline over
     *                    dart:io Directory.listSync().
     *   - RN iOS:        SHOULD be populated via FileManager.contentsOfDirectory.
     *
     * User-visible impact when this slot is NULL: model registry refresh with
     * `rescan_local = true` cannot link on-disk model folders to registered
     * entries — the warning in `ModelRegistryRefreshResult.warnings` is the
     * only signal to consuming code that the local rescan was skipped.
     */
    rac_file_list_directory_fn file_list_directory;

    // -------------------------------------------------------------------------
    // Directory Probe (Optional - can be NULL)
    // -------------------------------------------------------------------------

    /**
     * Check whether a path is a directory containing at least one entry.
     *
     * Optional. Used by the canonical RAModelInfo factory
     * (rac_model_info_make_proto) to compute the `is_downloaded` field for
     * directory-based artifacts (multi-file, archive-extracted) without
     * forcing the SDK to enumerate the directory itself. When NULL, commons
     * falls back to `file_list_directory` + entry-count; if BOTH are NULL,
     * `rac_path_is_non_empty_directory()` returns RAC_FALSE and
     * `is_downloaded` reports false for every directory-based artifact.
     *
     * Cross-SDK status (populate on every platform whose runtime exposes a
     * cheap directory probe — falling back to file_list_directory is
     * acceptable but pays the enumeration cost):
     *   - Web:           POPULATED (registerIsNonEmptyDirectory).
     *   - Swift / RN iOS / Kotlin / RN Android / Flutter: SHOULD be populated
     *     directly when the platform exposes a non-enumerating probe, otherwise
     *     rely on the file_list_directory fallback above.
     *
     * User-visible impact when BOTH slots are NULL: multi-file model artifacts
     * (e.g. mmproj + GGUF pairs, tokenizer + ONNX bundles) always report
     * `is_downloaded == false`, which silently disables the example-app
     * download-button gating and ranks downloaded models below unfetched ones
     * in registry listings.
     *
     * Error-conflation contract (NORMATIVE): the boolean return deliberately
     * collapses "missing" / "empty" / "regular file" / "platform probe error"
     * into a single RAC_FALSE. Commons treats RAC_FALSE as "not a usable
     * directory" and falls back to `file_exists` for the single-file case
     * (see rac_model_info_make_proto), so a transient platform error degrades
     * gracefully to `is_downloaded == false` rather than surfacing a structured
     * error. Implementations that hit a genuine platform fault (vs. a clean
     * missing/empty path) SHOULD emit a RAC_LOG_WARN via the adapter's `log`
     * slot (category "PlatformAdapter") so prod telemetry can detect
     * adapter-misconfiguration even though the C ABI return cannot distinguish
     * it. Promoting the signature to
     * `rac_result_t (*)(const char*, rac_bool_t* out, void*)` would let callers
     * branch on the fault, but is an ABI break requiring synchronized updates to
     * every SDK populator (Web/Kotlin-JNI/RN/Flutter), the commons consumer, and
     * the test mocks, and is intentionally deferred to a dedicated cross-SDK
     * change.
     *
     * @param path Absolute directory path (UTF-8, NUL-terminated).
     * @param user_data Platform context.
     * @return RAC_TRUE when the path is a directory with at least one entry;
     *         RAC_FALSE otherwise (missing, empty, a regular file, or a probe
     *         error — see the error-conflation contract above).
     */
    rac_bool_t (*is_non_empty_directory)(const char* path, void* user_data);

    // -------------------------------------------------------------------------
    // Vendor ID (Optional - can be NULL)
    // -------------------------------------------------------------------------

    /**
     * Apple-specific: returns the platform's persistent vendor ID
     * (UIDevice.identifierForVendor.uuidString on iOS).
     *
     * Used by rac_device_get_or_create_persistent_id() as a stable fallback
     * when the secure-storage cache miss occurs. NULL on non-Apple platforms
     * or when the platform cannot supply a vendor ID; commons then synthesizes
     * a fresh UUID and persists it via secure_set.
     *
     * Buffer should be >= 37 bytes (UUID string + NUL).
     *
     * Cross-SDK status (Apple-only — non-Apple SDKs MUST leave this NULL,
     * Apple-bridged SDKs SHOULD populate it so device-id is stable across
     * keychain wipes and matches Swift/iOS behaviour):
     *   - Web:           POPULATED (registerGetVendorId — no-op on non-Apple,
     *                    used by Safari/WKWebView when available).
     *   - Swift (iOS):   POPULATED (CppBridge+PlatformAdapter.swift wires
     *                    UIDevice.identifierForVendor.uuidString).
     *   - RN iOS:        SHOULD be populated via the same UIDevice API in the
     *                    InitBridge platform-adapter struct.
     *   - Flutter iOS:   SHOULD be populated via a Dart FFI trampoline that
     *                    invokes the iOS platform channel for identifierForVendor.
     *   - Kotlin / RN Android / Flutter Android: leave NULL (Android has no
     *                    equivalent stable per-app vendor ID; commons
     *                    synthesizes + persists a UUID instead).
     *
     * User-visible impact when this slot is NULL on Apple: every fresh
     * install / keychain reset produces a new device ID, which breaks
     * analytics identity continuity and forces license re-activation.
     *
     * @param out_buffer  Caller-provided buffer to receive the UUID string.
     * @param buffer_size Buffer size in bytes; MUST be >= 37 to succeed.
     * @param user_data   Platform context.
     * @return RAC_SUCCESS on success (out_buffer is NUL-terminated).
     *         On any error the buffer contents are unspecified and MUST NOT be
     *         consumed by the caller.
     */
    rac_result_t (*get_vendor_id)(char* out_buffer, size_t buffer_size, void* user_data);

    // -------------------------------------------------------------------------
    // User Data
    // -------------------------------------------------------------------------

    /** Platform-specific context passed to all callbacks */
    void* user_data;

} rac_platform_adapter_t;

// =============================================================================
// PLATFORM ADAPTER API
// =============================================================================

/**
 * Sets the platform adapter.
 *
 * Called during rac_init() - the adapter pointer must remain valid
 * until rac_shutdown() is called.
 *
 * @param adapter Platform adapter (must not be NULL)
 * @return RAC_SUCCESS on success, error code on failure
 */
RAC_API rac_result_t rac_set_platform_adapter(const rac_platform_adapter_t* adapter);

/**
 * Gets the current platform adapter.
 *
 * @return The current adapter, or NULL if not set
 */
RAC_API const rac_platform_adapter_t* rac_get_platform_adapter(void);

// =============================================================================
// CONVENIENCE FUNCTIONS (use platform adapter internally)
// =============================================================================

/**
 * Log a message using the platform adapter.
 * @param level Log level
 * @param category Category string
 * @param message Message string
 */
RAC_API void rac_log(rac_log_level_t level, const char* category, const char* message);

/**
 * Get current time in milliseconds.
 * @return Current time in milliseconds since epoch
 */
RAC_API int64_t rac_get_current_time_ms(void);

/**
 * Start an HTTP download using the platform adapter.
 * Returns RAC_ERROR_NOT_SUPPORTED if http_download callback is NULL.
 *
 * @param url URL to download
 * @param destination_path Where to save
 * @param progress_callback Progress callback (can be NULL)
 * @param complete_callback Completion callback
 * @param callback_user_data User data for callbacks
 * @param out_task_id Output: Task ID (owned, must be freed)
 * @return RAC_SUCCESS if started, error code otherwise
 */
RAC_API rac_result_t rac_http_download(const char* url, const char* destination_path,
                                       rac_http_progress_callback_fn progress_callback,
                                       rac_http_complete_callback_fn complete_callback,
                                       void* callback_user_data, char** out_task_id);

/**
 * Cancel an HTTP download.
 * Returns RAC_ERROR_NOT_SUPPORTED if http_download_cancel callback is NULL.
 *
 * @param task_id Task ID to cancel
 * @return RAC_SUCCESS if cancelled, error code otherwise
 */
RAC_API rac_result_t rac_http_download_cancel(const char* task_id);

/**
 * Extract an archive using the platform adapter.
 * Returns RAC_ERROR_NOT_SUPPORTED if extract_archive callback is NULL.
 *
 * @param archive_path Path to archive
 * @param destination_dir Where to extract
 * @param progress_callback Progress callback (can be NULL)
 * @param callback_user_data User data for callback
 * @return RAC_SUCCESS if extracted, error code otherwise
 */
RAC_API rac_result_t rac_extract_archive(const char* archive_path, const char* destination_dir,
                                         rac_extract_progress_callback_fn progress_callback,
                                         void* callback_user_data);

/**
 * Check if a model framework is a platform service (Swift-native).
 * Platform services are handled via service registry callbacks, not C++ backends.
 *
 * @param framework Framework to check
 * @return RAC_TRUE if platform service, RAC_FALSE if C++ backend
 */
RAC_API rac_bool_t rac_framework_is_platform_service(rac_inference_framework_t framework);

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLATFORM_ADAPTER_H */
