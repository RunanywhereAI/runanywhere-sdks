// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Archive extraction — libarchive-backed unpacker with zip-slip protection.
// Ports the capability surface from `sdk/runanywhere-commons/include/rac/
// infrastructure/extraction/rac_extraction.h`.
//
// Supports the formats the legacy commons supported: ZIP, TAR, TAR.GZ,
// TAR.BZ2, TAR.XZ. The underlying libarchive handles the format
// detection automatically.
//
// Zip-slip: every extracted path is validated against the destination
// root. Anything that escapes the root (via `..` segments, absolute
// paths, or symlinks pointing outside) is refused with
// RA_EX_ZIP_SLIP_DETECTED.

#ifndef RA_CORE_UTIL_EXTRACTION_H
#define RA_CORE_UTIL_EXTRACTION_H

#include <cstddef>
#include <cstdint>
#include <functional>
#include <string>
#include <string_view>

#include "../abi/ra_primitives.h"

namespace ra::core::util {

struct ExtractionProgress {
    std::size_t bytes_extracted = 0;
    std::size_t entries_done    = 0;
};

struct ExtractionResult {
    bool        ok              = false;
    ra_status_t status          = RA_ERR_INTERNAL;
    std::string error_detail;
    std::size_t entries_total   = 0;
    std::size_t bytes_total     = 0;
};

using ExtractionProgressCallback =
    std::function<void(const ExtractionProgress&)>;

// Extract `archive_path` into `dest_dir`. Creates `dest_dir` if it
// doesn't exist. Returns result.ok=true on success. Refuses any entry
// whose final path isn't a descendant of `dest_dir` — that rule blocks
// zip-slip, symlink escape, and absolute-path attacks.
ExtractionResult extract_archive(std::string_view archive_path,
                                   std::string_view dest_dir,
                                   ExtractionProgressCallback on_progress = {});

// Lists entries without extracting. Returns result.entries_total populated
// and entry_names[i] strings via the callback.
struct ArchiveEntry {
    std::string path;
    std::size_t size       = 0;
    bool        is_dir     = false;
    bool        is_symlink = false;
};
using ArchiveEntryCallback = std::function<void(const ArchiveEntry&)>;

ExtractionResult list_archive(std::string_view archive_path,
                                ArchiveEntryCallback on_entry);

}  // namespace ra::core::util

#endif  // RA_CORE_UTIL_EXTRACTION_H
