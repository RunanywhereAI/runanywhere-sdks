/**
 * PlatformDownloadBridge.h
 *
 * C callbacks for platform HTTP download progress/completion reporting used
 * by the RACommons platform-adapter HTTP download pipeline. iOS/Android
 * platform adapters call these from native-side async download delegates to
 * report progress/completion back to the `platformHttpDownloadCallback`
 * chain in `InitBridge.cpp`.
 *
 * NOTE: The `SyncHttpDownload` C++ wrapper that previously lived here was
 * the B-RN-3-001 / G-A6 workaround around libcurl HTTPS on Android. It was
 * removed in Task M5 — `HybridRunAnywhereCore::downloadModel` now goes
 * straight through `rac_http_download_execute`, which uses the registered
 * platform HTTP transport (OkHttp / URLSession) wired by Task M1.2.
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
#endif

#endif // RUNANYWHERE_PLATFORM_DOWNLOAD_BRIDGE_H
