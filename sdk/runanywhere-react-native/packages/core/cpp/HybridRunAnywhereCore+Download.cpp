/**
 * HybridRunAnywhereCore+Download.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 */
#include "HybridRunAnywhereCore+Common.hpp"
#include "bridges/PlatformDownloadBridge.h"

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

// Download Service
// ============================================================================
// B-RN-3-001 fix (original): route model downloads through the platform-adapter
// HTTP runner (Java HttpURLConnection on Android, NSURLSession on iOS) instead
// of `rac_http_download_execute`.
//
// Round-1 CPP fix (Task 4 / G-A6): CURL_DISABLE_HTTPS=ON has been removed from
// the Android libcurl build in commons CMakeLists.txt.  libcurl on Android now
// compiles with HTTPS enabled (backed by the NDK system SSL).  The platform-
// adapter path below is retained for backward compatibility and reliability;
// switch to `rac_http_download_execute` once end-to-end HTTPS is validated on
// all Android ABIs.
// ============================================================================

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::downloadModel(
    const std::string& url,
    const std::string& destPath,
    const std::string& cancelToken,
    const std::function<void(double, double)>& onProgress) {
    return Promise<void>::async([this, url, destPath, cancelToken, onProgress]() -> void {
        LOGI("Starting native download (platform adapter): %s -> %s",
             url.c_str(), destPath.c_str());

        auto cancelFlag = downloadCancelRegistry().registerToken(cancelToken);

        auto progressAdapter = [onProgress](int64_t downloaded, int64_t total) {
            if (onProgress) {
                onProgress(static_cast<double>(downloaded),
                           static_cast<double>(total));
            }
        };

        int rc = ::runanywhere::platform::SyncHttpDownload(
            url, destPath, progressAdapter, cancelFlag);

        downloadCancelRegistry().release(cancelToken);

        if (rc == RAC_SUCCESS) {
            LOGI("Download complete: %s", destPath.c_str());
            return;
        }

        std::string reason;
        switch (rc) {
            case RAC_ERROR_CANCELLED: reason = "cancelled"; break;
            case RAC_ERROR_TIMEOUT: reason = "timeout"; break;
            case RAC_ERROR_NETWORK_ERROR: reason = "network_error"; break;
            case RAC_ERROR_NETWORK_UNAVAILABLE: reason = "network_unavailable"; break;
            case RAC_ERROR_INVALID_PATH: reason = "invalid_path"; break;
            case RAC_ERROR_INVALID_ARGUMENT: reason = "invalid_argument"; break;
            case RAC_ERROR_DOWNLOAD_FAILED: reason = "download_failed"; break;
            case RAC_ERROR_NOT_SUPPORTED: reason = "not_supported"; break;
            default: reason = "unknown"; break;
        }
        std::string msg = "download failed: " + reason + " (status=" +
                          std::to_string(rc) + ")";
        LOGE("%s", msg.c_str());
        setLastError(msg);
        throw std::runtime_error(msg);
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::cancelDownload(
    const std::string& cancelToken) {
    return Promise<bool>::async([cancelToken]() -> bool {
        bool cancelled = downloadCancelRegistry().cancel(cancelToken);
        if (cancelled) {
            LOGI("Cancelled download: %s", cancelToken.c_str());
        }
        return cancelled;
    });
}

} // namespace margelo::nitro::runanywhere
