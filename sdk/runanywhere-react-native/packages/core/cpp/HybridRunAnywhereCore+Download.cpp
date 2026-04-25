/**
 * HybridRunAnywhereCore+Download.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 */
#include "HybridRunAnywhereCore+Common.hpp"

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

// Download Service
// ============================================================================
// Download Service — libcurl-backed runner (rac_http_download_execute) with
// cancel-token registry. Replaces the RNFS/job-id plumbing that used to live
// in FileSystem.ts.
// ============================================================================

namespace {

// Progress trampoline — forwards rac_http_download progress to the JS callback
// and honours the cancel flag registered against the caller's token.
struct DownloadProgressContext {
    std::function<void(double, double)> onProgress;
    std::shared_ptr<std::atomic<bool>> cancelFlag;
};

rac_bool_t downloadProgressTrampoline(uint64_t bytesWritten, uint64_t totalBytes,
                                      void* userData) {
    auto* ctx = static_cast<DownloadProgressContext*>(userData);
    if (!ctx) return RAC_TRUE;
    if (ctx->cancelFlag && ctx->cancelFlag->load()) {
        return RAC_FALSE;
    }
    if (ctx->onProgress) {
        ctx->onProgress(static_cast<double>(bytesWritten),
                        static_cast<double>(totalBytes));
    }
    return RAC_TRUE;
}

} // anonymous namespace

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::downloadModel(
    const std::string& url,
    const std::string& destPath,
    const std::string& cancelToken,
    const std::function<void(double, double)>& onProgress) {
    return Promise<void>::async([this, url, destPath, cancelToken, onProgress]() -> void {
        LOGI("Starting native download: %s -> %s", url.c_str(), destPath.c_str());

        auto cancelFlag = downloadCancelRegistry().registerToken(cancelToken);

        DownloadProgressContext ctx{onProgress, cancelFlag};

        rac_http_download_request_t req{};
        req.url = url.c_str();
        req.destination_path = destPath.c_str();
        req.headers = nullptr;
        req.header_count = 0;
        req.timeout_ms = 0;  // no timeout — model downloads can be large
        req.follow_redirects = RAC_TRUE;
        req.resume_from_byte = 0;
        req.expected_sha256_hex = nullptr;

        int32_t httpStatus = 0;
        rac_http_download_status_t status = rac_http_download_execute(
            &req, downloadProgressTrampoline, &ctx, &httpStatus);

        downloadCancelRegistry().release(cancelToken);

        if (status == RAC_HTTP_DL_OK) {
            LOGI("Download complete: %s", destPath.c_str());
            return;
        }

        std::string reason;
        switch (status) {
            case RAC_HTTP_DL_CANCELLED: reason = "cancelled"; break;
            case RAC_HTTP_DL_TIMEOUT: reason = "timeout"; break;
            case RAC_HTTP_DL_NETWORK_ERROR: reason = "network_error"; break;
            case RAC_HTTP_DL_NETWORK_UNAVAILABLE: reason = "network_unavailable"; break;
            case RAC_HTTP_DL_DNS_ERROR: reason = "dns_error"; break;
            case RAC_HTTP_DL_SSL_ERROR: reason = "ssl_error"; break;
            case RAC_HTTP_DL_SERVER_ERROR: reason = "server_error"; break;
            case RAC_HTTP_DL_FILE_ERROR: reason = "file_error"; break;
            case RAC_HTTP_DL_INSUFFICIENT_STORAGE: reason = "insufficient_storage"; break;
            case RAC_HTTP_DL_INVALID_URL: reason = "invalid_url"; break;
            case RAC_HTTP_DL_CHECKSUM_FAILED: reason = "checksum_failed"; break;
            default: reason = "unknown"; break;
        }
        std::string msg = "download failed: " + reason + " (status=" +
                          std::to_string(status) + ", http=" +
                          std::to_string(httpStatus) + ")";
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
