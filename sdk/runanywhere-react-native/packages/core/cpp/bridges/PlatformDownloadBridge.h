/**
 * PlatformDownloadBridge.h
 *
 * C callbacks for platform HTTP download progress/completion reporting.
 * Used by iOS/Android platform adapters to report async download state
 * back into the C++ bridge.
 */

#ifndef RUNANYWHERE_PLATFORM_DOWNLOAD_BRIDGE_H
#define RUNANYWHERE_PLATFORM_DOWNLOAD_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Report HTTP download progress for a task.
 * @param task_id Task identifier
 * @param downloaded_bytes Bytes downloaded so far
 * @param total_bytes Total bytes (0 if unknown)
 * @return RAC_SUCCESS on success, error code otherwise
 */
int RunAnywhereHttpDownloadReportProgress(const char* task_id,
                                          int64_t downloaded_bytes,
                                          int64_t total_bytes);

/**
 * Report HTTP download completion for a task.
 * @param task_id Task identifier
 * @param result RAC_SUCCESS or error code
 * @param downloaded_path Path to downloaded file (NULL on failure)
 * @return RAC_SUCCESS on success, error code otherwise
 */
int RunAnywhereHttpDownloadReportComplete(const char* task_id,
                                          int result,
                                          const char* downloaded_path);

#ifdef __cplusplus
} // extern "C"

#include <atomic>
#include <functional>
#include <memory>
#include <string>

namespace runanywhere::platform {

/**
 * Synchronous HTTP download via the platform adapter (Java HttpURLConnection on
 * Android, NSURLSession on iOS). Blocks until completion or cancel.
 *
 * Used as the canonical RN model-download transport — replaces the C++
 * `rac_http_download_execute` path which is HTTPS-disabled on Android
 * (B-RN-3-001). Returns RAC_SUCCESS or a negative error code matching
 * rac_result_t.
 *
 * @param url HTTPS URL
 * @param destinationPath Local destination path
 * @param onProgress Optional progress callback (downloaded, total)
 * @param cancelFlag Optional shared atomic — set true to cancel mid-download
 * @return 0 on success, negative error code on failure
 */
int SyncHttpDownload(
    const std::string& url,
    const std::string& destinationPath,
    const std::function<void(int64_t, int64_t)>& onProgress,
    const std::shared_ptr<std::atomic<bool>>& cancelFlag);

} // namespace runanywhere::platform
#endif

#endif // RUNANYWHERE_PLATFORM_DOWNLOAD_BRIDGE_H
