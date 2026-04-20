// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_extract.h"

#include <cstring>
#include <string>
#include <string_view>

#ifndef RA_NO_EXTRACTION
#  include "../util/extraction.h"
#endif

namespace {
bool ends_with(std::string_view s, std::string_view sfx) {
    return s.size() >= sfx.size() &&
        std::equal(s.end() - sfx.size(), s.end(), sfx.begin(), sfx.end());
}
}  // namespace

extern "C" {

ra_archive_type_t ra_detect_archive_type(const char* path) {
    if (!path) return RA_ARCHIVE_UNKNOWN;
    std::string_view s{path};
    if (ends_with(s, ".zip"))     return RA_ARCHIVE_ZIP;
    if (ends_with(s, ".tar.gz") || ends_with(s, ".tgz")) return RA_ARCHIVE_TAR_GZ;
    if (ends_with(s, ".tar.bz2")) return RA_ARCHIVE_TAR_BZ2;
    if (ends_with(s, ".tar.xz"))  return RA_ARCHIVE_TAR_XZ;
    if (ends_with(s, ".tar"))     return RA_ARCHIVE_TAR;
    return RA_ARCHIVE_UNKNOWN;
}

ra_status_t ra_extract_archive_native(const char*                       archive_path,
                                       const char*                       destination_dir,
                                       ra_extract_progress_callback_fn   progress_cb,
                                       void*                             user_data) {
    if (!archive_path || !destination_dir) return RA_ERR_INVALID_ARGUMENT;
#ifdef RA_NO_EXTRACTION
    (void)progress_cb; (void)user_data;
    return RA_ERR_CAPABILITY_UNSUPPORTED;
#else
    auto result = ra::core::util::extract_archive(
        archive_path, destination_dir,
        [&](const ra::core::util::ExtractionProgress& p) {
            if (progress_cb) progress_cb(static_cast<int32_t>(p.entries_done),
                                          0, user_data);
        });
    return result.ok ? RA_OK : result.status;
#endif
}

}  // extern "C"
