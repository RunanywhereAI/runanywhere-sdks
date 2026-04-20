// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — archive extraction C ABI.
//
// Wraps `core/util/extraction.h`. On platforms without libarchive
// (RA_NO_EXTRACTION), each call returns RA_ERR_CAPABILITY_UNSUPPORTED;
// frontends fall back to `ra_extract_archive_via_adapter` (platform native).

#ifndef RA_EXTRACT_H
#define RA_EXTRACT_H

#include <stddef.h>
#include <stdint.h>

#include "ra_primitives.h"
#include "ra_platform_adapter.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t ra_archive_type_t;
enum {
    RA_ARCHIVE_UNKNOWN = 0,
    RA_ARCHIVE_ZIP     = 1,
    RA_ARCHIVE_TAR     = 2,
    RA_ARCHIVE_TAR_GZ  = 3,
    RA_ARCHIVE_TAR_BZ2 = 4,
    RA_ARCHIVE_TAR_XZ  = 5,
};

ra_archive_type_t ra_detect_archive_type(const char* path);

// Extract using the bundled libarchive backend when available. Returns
// RA_ERR_CAPABILITY_UNSUPPORTED when the core was built with
// RA_BUILD_EXTRACTION=OFF; in that case use ra_extract_archive_via_adapter.
ra_status_t ra_extract_archive_native(const char*                       archive_path,
                                       const char*                       destination_dir,
                                       ra_extract_progress_callback_fn   progress_cb,
                                       void*                             user_data);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_EXTRACT_H
