/**
 * @file DownloadBridge.hpp
 * @brief Download-manager lifecycle bridge.
 *
 * Owns the `rac_download_manager_*` handle created at SDK init and destroyed at
 * teardown. The download workflow itself (plan/start/cancel/resume + progress
 * streaming) is transported as serialized `runanywhere.v1` proto bytes through
 * `HybridRunAnywhereCore+Download.cpp` (the `rac_download_*_proto` ABI), so
 * progress state crosses the JSI boundary as proto-canonical bytes and is
 * decoded directly by `@runanywhere/proto-ts/download_service`. There are no
 * hand-written progress/state enums here — that would re-introduce the
 * off-by-one drift versus the proto numbering.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Download.swift
 */

#pragma once

#include "rac_types.h"
#include "rac_download.h"

namespace runanywhere {
namespace bridges {

/**
 * Download manager configuration
 */
struct DownloadConfig {
    int32_t maxConcurrentDownloads = 1;
    int32_t requestTimeoutSeconds = 60;
    int32_t maxRetryAttempts = 3;
    int32_t retryDelaySeconds = 5;
    bool allowCellular = true;
    bool allowConstrainedNetwork = false;
};

/**
 * DownloadBridge - owns the `rac_download_manager_*` handle lifecycle.
 *
 * Created during SDK init and destroyed during teardown. The actual download
 * orchestration flows through the `rac_download_*_proto` ABI, mirroring Swift's
 * `CppBridge.Download` actor.
 */
class DownloadBridge {
public:
    static DownloadBridge& shared();

    /**
     * Create the download manager.
     * @param config Optional configuration
     */
    rac_result_t initialize(const DownloadConfig* config = nullptr);

    /**
     * Destroy the download manager.
     */
    void shutdown();

    bool isInitialized() const { return handle_ != nullptr; }

private:
    DownloadBridge() = default;
    ~DownloadBridge();
    DownloadBridge(const DownloadBridge&) = delete;
    DownloadBridge& operator=(const DownloadBridge&) = delete;

    rac_download_manager_handle_t handle_ = nullptr;
};

} // namespace bridges
} // namespace runanywhere
