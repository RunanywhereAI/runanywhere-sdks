// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "storage_analyzer.h"

#include <filesystem>
#include <system_error>

#include "file_manager.h"

namespace ra::core::util {

namespace fs = std::filesystem;

DiskSpace disk_space_for(std::string_view path) {
    DiskSpace out;
    std::error_code ec;
    const auto s = fs::space(fs::path(std::string{path}), ec);
    if (ec) return out;
    out.capacity_bytes  = static_cast<std::uint64_t>(s.capacity);
    out.free_bytes      = static_cast<std::uint64_t>(s.free);
    out.available_bytes = static_cast<std::uint64_t>(s.available);
    return out;
}

std::vector<ModelStorageInfo> list_models_with_size() {
    std::vector<ModelStorageInfo> out;
    const auto root = models_dir();
    std::error_code ec;
    if (!fs::is_directory(root, ec)) return out;

    // Layout: {root}/{framework}/{model_id}/
    for (auto& fw_entry : fs::directory_iterator(root, ec)) {
        if (ec) break;
        if (!fw_entry.is_directory(ec)) continue;
        const auto framework = fw_entry.path().filename().string();
        for (auto& mdl_entry : fs::directory_iterator(fw_entry.path(), ec)) {
            if (ec) break;
            if (!mdl_entry.is_directory(ec)) continue;
            ModelStorageInfo info;
            info.model_id   = mdl_entry.path().filename().string();
            info.framework  = framework;
            info.path       = mdl_entry.path().string();
            info.size_bytes = directory_size_bytes(info.path);
            out.push_back(std::move(info));
        }
    }
    return out;
}

}  // namespace ra::core::util
