// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Platform-agnostic model downloader. Implementations live in
// model_downloader_<platform>.cpp. The frontend passes a progress callback
// that emits percentage updates to the UI.

#ifndef RA_CORE_MODEL_DOWNLOADER_H
#define RA_CORE_MODEL_DOWNLOADER_H

#include <functional>
#include <memory>
#include <string>
#include <string_view>

#include "ra_primitives.h"

namespace ra::core {

struct DownloadProgress {
    std::size_t bytes_downloaded = 0;
    std::size_t total_bytes      = 0;
    double      percent          = 0.0;
};

class ModelDownloader {
public:
    using ProgressCallback = std::function<void(const DownloadProgress&)>;

    virtual ~ModelDownloader() = default;

    // Synchronous download. Returns RA_OK on success. On failure, partial
    // files are cleaned up. Thread-safe.
    virtual ra_status_t fetch(std::string_view url,
                               std::string_view dest_path,
                               std::string_view expected_sha256,
                               ProgressCallback on_progress) = 0;

    // Factory — returns the best downloader for the current platform.
    static std::unique_ptr<ModelDownloader> create();
};

}  // namespace ra::core

#endif  // RA_CORE_MODEL_DOWNLOADER_H
