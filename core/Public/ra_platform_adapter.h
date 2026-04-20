// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — platform adapter C ABI.
//
// The platform adapter is a struct of function pointers that the frontend
// SDK fills in at startup, letting the C core delegate platform-specific
// operations back to Swift / Kotlin / Dart / JS. Ports the capability
// surface from `sdk/legacy/commons/include/rac/core/rac_platform_adapter.h`.
//
// Contract:
//   * A single process-wide adapter. Frontends call ra_set_platform_adapter
//     once during init. The adapter pointer must outlive the SDK.
//   * Every callback takes a trailing `void* user_data` that the frontend
//     uses to carry its own context (e.g. a Swift class ref retained by
//     Unmanaged.passRetained).
//   * All adapter callbacks may be NULL when unsupported; helpers return
//     RA_ERR_CAPABILITY_UNSUPPORTED in that case.

#ifndef RA_PLATFORM_ADAPTER_H
#define RA_PLATFORM_ADAPTER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "ra_primitives.h"

#ifdef __cplusplus
extern "C" {
#endif

// --- Log levels -------------------------------------------------------------
typedef int32_t ra_log_level_t;
enum {
    RA_LOG_LEVEL_TRACE = 0,
    RA_LOG_LEVEL_DEBUG = 1,
    RA_LOG_LEVEL_INFO  = 2,
    RA_LOG_LEVEL_WARN  = 3,
    RA_LOG_LEVEL_ERROR = 4,
    RA_LOG_LEVEL_FATAL = 5,
};

// --- Memory info ------------------------------------------------------------
typedef struct {
    uint64_t total_bytes;
    uint64_t available_bytes;
    uint64_t used_bytes;
    uint64_t app_bytes;       // resident set size for this process
} ra_memory_info_t;

// --- HTTP download callback shapes -----------------------------------------
typedef void (*ra_http_progress_callback_fn)(int64_t bytes_downloaded,
                                              int64_t total_bytes,
                                              void*   callback_user_data);
typedef void (*ra_http_complete_callback_fn)(ra_status_t  result,
                                              const char*  downloaded_path,
                                              void*        callback_user_data);
typedef void (*ra_extract_progress_callback_fn)(int32_t files_extracted,
                                                 int32_t total_files,
                                                 void*   callback_user_data);

// --- Platform adapter struct -----------------------------------------------
//
// Mirrors legacy `rac_platform_adapter_t` field-for-field so a Swift
// bridging layer can keep the same mental model.
typedef struct ra_platform_adapter {
    // File system --------------------------------------------------------
    uint8_t      (*file_exists)(const char* path, void* user_data);       // 0/1
    ra_status_t  (*file_read)(const char* path, void** out_data,
                               size_t* out_size, void* user_data);
    ra_status_t  (*file_write)(const char* path, const void* data,
                                size_t size, void* user_data);
    ra_status_t  (*file_delete)(const char* path, void* user_data);

    // Secure storage (Keychain / KeyStore / Credential Manager) ---------
    ra_status_t  (*secure_get)(const char* key, char** out_value,
                                void* user_data);
    ra_status_t  (*secure_set)(const char* key, const char* value,
                                void* user_data);
    ra_status_t  (*secure_delete)(const char* key, void* user_data);

    // Logging ------------------------------------------------------------
    void         (*log)(ra_log_level_t level, const char* category,
                         const char* message, void* user_data);

    // Telemetry / Sentry ------------------------------------------------
    void         (*track_error)(const char* error_json, void* user_data);

    // Clock --------------------------------------------------------------
    int64_t      (*now_ms)(void* user_data);

    // Memory info --------------------------------------------------------
    ra_status_t  (*get_memory_info)(ra_memory_info_t* out_info, void* user_data);

    // HTTP download (optional — may be NULL; core falls back to libcurl) -
    ra_status_t  (*http_download)(const char* url, const char* destination_path,
                                   ra_http_progress_callback_fn progress_callback,
                                   ra_http_complete_callback_fn complete_callback,
                                   void* callback_user_data,
                                   char** out_task_id, void* user_data);
    ra_status_t  (*http_download_cancel)(const char* task_id, void* user_data);

    // Archive extraction (optional — may be NULL; core falls back to libarchive).
    ra_status_t  (*extract_archive)(const char* archive_path,
                                     const char* destination_dir,
                                     ra_extract_progress_callback_fn progress_callback,
                                     void* callback_user_data, void* user_data);

    // User data passed to every callback (frontend context)
    void*        user_data;
} ra_platform_adapter_t;

// --- Registration -----------------------------------------------------------
//
// Set the process-wide adapter. The pointer MUST outlive the SDK — the
// core stores a shallow copy of the struct. Passing NULL resets to the
// default (no adapter — helpers return RA_ERR_CAPABILITY_UNSUPPORTED).
ra_status_t ra_set_platform_adapter(const ra_platform_adapter_t* adapter);

// Returns the registered adapter, or NULL when none is set.
const ra_platform_adapter_t* ra_get_platform_adapter(void);

// --- Convenience helpers ----------------------------------------------------
//
// These route through the registered adapter when set, otherwise fall
// back to process-local defaults (stderr logging, std::chrono for time).

void     ra_log(ra_log_level_t level, const char* category, const char* message);
int64_t  ra_get_current_time_ms(void);

// Fires the registered adapter's http_download callback if present,
// else returns RA_ERR_CAPABILITY_UNSUPPORTED.
ra_status_t ra_http_download(const char* url, const char* destination_path,
                              ra_http_progress_callback_fn progress_callback,
                              ra_http_complete_callback_fn complete_callback,
                              void* callback_user_data, char** out_task_id);
ra_status_t ra_http_download_cancel(const char* task_id);
ra_status_t ra_extract_archive_via_adapter(const char* archive_path,
                                            const char* destination_dir,
                                            ra_extract_progress_callback_fn progress_callback,
                                            void* callback_user_data);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_PLATFORM_ADAPTER_H
