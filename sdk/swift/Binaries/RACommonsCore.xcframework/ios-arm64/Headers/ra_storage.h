// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — storage analyzer C ABI.
//
// Reports disk capacity / free space for a path and enumerates models with
// their on-disk sizes. Wraps `core/util/storage_analyzer.h`.

#ifndef RA_STORAGE_H
#define RA_STORAGE_H

#include <stddef.h>
#include <stdint.h>

#include "ra_primitives.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int64_t capacity_bytes;
    int64_t free_bytes;
    int64_t available_bytes;
} ra_storage_disk_space_t;

typedef struct {
    char*   model_id;
    char*   framework;
    char*   path;
    int64_t size_bytes;
} ra_storage_model_info_t;

// ---------------------------------------------------------------------------
// Disk reporting
// ---------------------------------------------------------------------------
ra_status_t ra_storage_disk_space_for(const char* path,
                                       ra_storage_disk_space_t* out_info);

// Returns 1 if `required_bytes` ≤ available_bytes for `path`.
uint8_t     ra_storage_can_fit(const char* path, int64_t required_bytes);

// ---------------------------------------------------------------------------
// Model enumeration
// ---------------------------------------------------------------------------

// Returns a heap-allocated array of model entries (each with heap strings).
// Free with `ra_storage_model_info_array_free`.
ra_status_t ra_storage_list_models(ra_storage_model_info_t** out_models,
                                    int32_t*                  out_count);

void ra_storage_model_info_free(ra_storage_model_info_t* m);
void ra_storage_model_info_array_free(ra_storage_model_info_t* arr, int32_t count);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_STORAGE_H
