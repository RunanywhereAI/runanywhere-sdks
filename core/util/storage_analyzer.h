// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Disk-capacity reporter. Ports the capability surface from
// `sdk/runanywhere-commons/include/rac/infrastructure/storage/
// rac_storage_analyzer.h`.

#ifndef RA_CORE_UTIL_STORAGE_ANALYZER_H
#define RA_CORE_UTIL_STORAGE_ANALYZER_H

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace ra::core::util {

struct DiskSpace {
    std::uint64_t capacity_bytes = 0;
    std::uint64_t free_bytes     = 0;
    std::uint64_t available_bytes = 0;  // available to current user
};

// Reports total / free / available bytes for the filesystem containing
// `path`. Returns zeroed struct on error.
DiskSpace disk_space_for(std::string_view path);

struct ModelStorageInfo {
    std::string   model_id;
    std::string   framework;
    std::string   path;
    std::uint64_t size_bytes = 0;
};

// Enumerates every model directory under `models_dir()` and reports its
// size on disk. Useful for settings UIs that show how much storage each
// model is using.
std::vector<ModelStorageInfo> list_models_with_size();

}  // namespace ra::core::util

#endif  // RA_CORE_UTIL_STORAGE_ANALYZER_H
