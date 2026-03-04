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
#endif

#endif // RUNANYWHERE_PLATFORM_DOWNLOAD_BRIDGE_H
