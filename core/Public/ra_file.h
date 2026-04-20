// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — file manager C ABI.
//
// Wraps `core/util/file_manager.h` so frontends can manage SDK-owned
// folders (cache / tmp / models) without re-implementing path
// conventions. Mirrors the legacy `rac_file_manager_*` surface.

#ifndef RA_FILE_H
#define RA_FILE_H

#include <stddef.h>
#include <stdint.h>

#include "ra_primitives.h"

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Directory lifecycle
// ---------------------------------------------------------------------------
ra_status_t ra_file_create_directory(const char* path);
ra_status_t ra_file_remove_path(const char* path);          // recursive
uint8_t     ra_file_path_exists(const char* path);          // 0/1
uint8_t     ra_file_is_directory(const char* path);
uint8_t     ra_file_is_regular_file(const char* path);

// ---------------------------------------------------------------------------
// Listing — returns a heap array of strings; free with ra_file_string_array_free.
// ---------------------------------------------------------------------------
ra_status_t ra_file_list_directory(const char* path,
                                    char***     out_entries,
                                    int32_t*    out_count);
ra_status_t ra_file_list_directory_recursive(const char* path,
                                              char***     out_entries,
                                              int32_t*    out_count);

// ---------------------------------------------------------------------------
// Sizes
// ---------------------------------------------------------------------------
int64_t ra_file_directory_size_bytes(const char* path);
int64_t ra_file_size_bytes(const char* path);

// ---------------------------------------------------------------------------
// Canonical SDK directories — heap-allocated UTF-8 paths.
// Free with ra_file_string_free.
// ---------------------------------------------------------------------------
ra_status_t ra_file_app_support_dir(char** out_path);
ra_status_t ra_file_cache_dir(char** out_path);
ra_status_t ra_file_tmp_dir(char** out_path);
ra_status_t ra_file_models_dir(char** out_path);

// Build the conventional model path: {models_dir()}/{framework}/{model_id}/.
ra_status_t ra_file_model_path(const char* framework, const char* model_id,
                                char** out_path);

// ---------------------------------------------------------------------------
// Cleanup
// ---------------------------------------------------------------------------
int64_t ra_file_clear_cache(void);   // returns bytes reclaimed
int64_t ra_file_clear_tmp(void);

// ---------------------------------------------------------------------------
// Memory ownership
// ---------------------------------------------------------------------------
void ra_file_string_free(char* s);
void ra_file_string_array_free(char** arr, int32_t count);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_FILE_H
