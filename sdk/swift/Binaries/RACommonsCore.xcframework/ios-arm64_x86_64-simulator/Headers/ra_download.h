// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — model download manager C ABI.
//
// Wraps `core/model_registry/model_downloader.h` with a C-callable surface
// + a stateful manager that tracks active tasks (cancel/resume/pause).
// Mirrors the legacy `rac_download_manager_*` and orchestrator helpers
// from `rac_download.h` / `rac_download_orchestrator.h`.

#ifndef RA_DOWNLOAD_H
#define RA_DOWNLOAD_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "ra_primitives.h"

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Download state machine + progress payloads.
// ---------------------------------------------------------------------------
typedef int32_t ra_download_state_t;
enum {
    RA_DOWNLOAD_STATE_PENDING     = 0,
    RA_DOWNLOAD_STATE_DOWNLOADING = 1,
    RA_DOWNLOAD_STATE_EXTRACTING  = 2,
    RA_DOWNLOAD_STATE_COMPLETE    = 3,
    RA_DOWNLOAD_STATE_FAILED      = 4,
    RA_DOWNLOAD_STATE_CANCELLED   = 5,
    RA_DOWNLOAD_STATE_PAUSED      = 6,
};

typedef struct {
    int64_t             bytes_downloaded;
    int64_t             total_bytes;
    float               percent;            // 0-1
    ra_download_state_t state;
    int32_t             _reserved0;
} ra_download_progress_t;

typedef struct {
    char*               task_id;            // Heap-allocated; free with ra_download_task_free
    char*               url;                // Heap-allocated
    char*               destination_path;   // Heap-allocated
    int64_t             total_bytes;
    int64_t             bytes_downloaded;
    ra_download_state_t state;
    int32_t             _reserved0;
} ra_download_task_t;

typedef void (*ra_download_progress_callback_fn)(const ra_download_progress_t* progress,
                                                  void* user_data);
typedef void (*ra_download_complete_callback_fn)(ra_status_t  result,
                                                  const char*  task_id,
                                                  const char*  destination_path,
                                                  void*        user_data);

typedef struct ra_download_manager_s ra_download_manager_t;

// ---------------------------------------------------------------------------
// Manager lifecycle
// ---------------------------------------------------------------------------
ra_status_t ra_download_manager_create(ra_download_manager_t** out_manager);
void        ra_download_manager_destroy(ra_download_manager_t* manager);

// Returns the process-wide singleton manager; convenient for frontends that
// don't need multiple managers. Lifetime is the process; do NOT destroy it.
ra_download_manager_t* ra_download_manager_global(void);

// ---------------------------------------------------------------------------
// Task control
// ---------------------------------------------------------------------------

// Start a download. `out_task_id` is heap-allocated (free with ra_download_string_free).
ra_status_t ra_download_manager_start(ra_download_manager_t*           manager,
                                       const char*                      url,
                                       const char*                      destination_path,
                                       const char*                      expected_sha256,
                                       ra_download_progress_callback_fn progress_cb,
                                       ra_download_complete_callback_fn complete_cb,
                                       void*                            user_data,
                                       char**                           out_task_id);

ra_status_t ra_download_manager_cancel(ra_download_manager_t* manager, const char* task_id);
ra_status_t ra_download_manager_pause_all(ra_download_manager_t* manager);
ra_status_t ra_download_manager_resume_all(ra_download_manager_t* manager);

// Snapshot the progress of `task_id`.
ra_status_t ra_download_manager_get_progress(ra_download_manager_t*  manager,
                                              const char*             task_id,
                                              ra_download_progress_t* out_progress);

// Returns a heap-allocated array of currently-active task IDs. `out_count`
// receives the array length. Free `*out_ids` with `ra_download_task_ids_free`.
ra_status_t ra_download_manager_get_active_tasks(ra_download_manager_t* manager,
                                                  char***                out_ids,
                                                  int32_t*               out_count);

// ---------------------------------------------------------------------------
// Orchestrator helpers (compute paths, decide if extraction is needed, …)
// ---------------------------------------------------------------------------

// Returns 1 if `archive_path` ends in .zip / .tar / .tar.gz / .tar.bz2 / .tar.xz.
uint8_t ra_download_requires_extraction(const char* archive_path);

// Compute the destination path that the downloader should use for `model_id`
// + remote `url`. Heap-allocated; free with ra_download_string_free.
ra_status_t ra_download_compute_destination(const char* models_root,
                                             const char* model_id,
                                             const char* url,
                                             char**      out_path);

// After extraction, walks `extracted_dir` and returns the most likely
// model file (largest file matching *.gguf|*.onnx|*.bin|*.safetensors).
// Heap-allocated; free with ra_download_string_free.
ra_status_t ra_find_model_path_after_extraction(const char* extracted_dir,
                                                 char**      out_model_path);

// Full orchestrate: download → verify checksum → extract → return final path.
// Synchronous; wires `progress_cb` for both phases.
ra_status_t ra_download_orchestrate(const char* url,
                                     const char* destination_path,
                                     const char* expected_sha256,
                                     ra_download_progress_callback_fn progress_cb,
                                     void*                            user_data,
                                     char**                           out_final_path);

// Orchestrate with retry + exponential backoff. `max_retries` of 0 behaves
// identically to `ra_download_orchestrate`. On each retry the manager
// sleeps `base_backoff_ms << attempt` before trying again, capped at
// `max_backoff_ms`. Progress callback reflects the final attempt only.
ra_status_t ra_download_orchestrate_with_retry(
    const char* url,
    const char* destination_path,
    const char* expected_sha256,
    int32_t                          max_retries,
    int32_t                          base_backoff_ms,
    int32_t                          max_backoff_ms,
    ra_download_progress_callback_fn progress_cb,
    void*                            user_data,
    char**                           out_final_path);

// Compute SHA-256 of a file on disk and return the hex digest (64 chars
// lowercase). Heap-allocated; free with `ra_download_string_free`.
ra_status_t ra_download_sha256_file(const char* file_path, char** out_hex);

// Verify that `file_path` matches `expected_hex_sha256`. Returns RA_OK on
// match, RA_ERR_IO on mismatch, RA_ERR_INVALID_ARGUMENT on missing file.
ra_status_t ra_download_verify_sha256(const char* file_path,
                                        const char* expected_hex_sha256);

// ---------------------------------------------------------------------------
// Memory ownership
// ---------------------------------------------------------------------------
void ra_download_string_free(char* s);
void ra_download_task_free(ra_download_task_t* task);
void ra_download_task_ids_free(char** ids, int32_t count);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_DOWNLOAD_H
