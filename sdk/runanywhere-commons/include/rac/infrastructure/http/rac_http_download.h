/**
 * @file rac_http_download.h
 * @brief Blocking file download runner built on `rac_http_client_*`.
 *
 * v2 close-out Phase H. Owns the end-to-end download primitive that
 * used to live in Kotlin's CppBridgeDownload.kt (HttpURLConnection
 * loop + FileOutputStream + SHA-256 verify + Range-based resume).
 *
 * Single entry point: `rac_http_download_execute`. Synchronous —
 * callers spawn their own thread. Progress callback fires on every
 * chunk (throttled inside the runner to at most every 100 ms), and
 * returns `RAC_FALSE` to cancel.
 *
 * Checksum verification runs inline on the stream (no second pass
 * over the file on disk), so even multi-GB downloads stay O(1) in
 * memory.
 */

#ifndef RAC_INFRASTRUCTURE_HTTP_RAC_HTTP_DOWNLOAD_H
#define RAC_INFRASTRUCTURE_HTTP_RAC_HTTP_DOWNLOAD_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_types.h"
#include "rac/infrastructure/http/rac_http_client.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// STATUS
// =============================================================================
// Status codes match the Kotlin `DownloadError` enum in
// CppBridgeDownload.kt so the JNI bridge can forward them verbatim.
// Do not reorder without updating the Kotlin side.
typedef enum {
    RAC_HTTP_DL_OK                    = 0,
    RAC_HTTP_DL_NETWORK_ERROR         = 1,
    RAC_HTTP_DL_FILE_ERROR            = 2,
    RAC_HTTP_DL_INSUFFICIENT_STORAGE  = 3,
    RAC_HTTP_DL_INVALID_URL           = 4,
    RAC_HTTP_DL_CHECKSUM_FAILED       = 5,
    RAC_HTTP_DL_CANCELLED             = 6,
    RAC_HTTP_DL_SERVER_ERROR          = 7,
    RAC_HTTP_DL_TIMEOUT               = 8,
    RAC_HTTP_DL_NETWORK_UNAVAILABLE   = 9,
    RAC_HTTP_DL_DNS_ERROR             = 10,
    RAC_HTTP_DL_SSL_ERROR             = 11,
    RAC_HTTP_DL_UNKNOWN               = 99
} rac_http_download_status_t;

// =============================================================================
// REQUEST
// =============================================================================

typedef struct {
    const char* url;
    const char* destination_path;

    // Extra request headers (optional). Owned by caller.
    const rac_http_header_kv_t* headers;
    size_t header_count;

    int32_t timeout_ms;            // 0 = no timeout
    rac_bool_t follow_redirects;   // RAC_TRUE recommended

    // When > 0, resume from this byte offset (Range: bytes=N-) and
    // open the destination file in append mode. When 0, start fresh
    // (truncate the destination).
    uint64_t resume_from_byte;

    // Optional lowercase hex SHA-256. NULL to skip verification.
    const char* expected_sha256_hex;
} rac_http_download_request_t;

// =============================================================================
// CALLBACK
// =============================================================================

/**
 * @brief Progress callback. Fires on every chunk libcurl delivers
 * (typically ~16 KiB each), plus a final call with `bytes_written ==
 * total_bytes` on clean completion. No time-based throttling is
 * applied inside the runner — callers that want UI-update frequency
 * throttling should do it in their callback.
 *
 * @param bytes_written Total bytes written to disk (including the
 *        resume-from prefix).
 * @param total_bytes   Total download size including resume prefix,
 *        or 0 when the server did not send Content-Length.
 * @param user_data     Opaque.
 * @return RAC_FALSE to cancel (the runner aborts libcurl and returns
 *         `RAC_HTTP_DL_CANCELLED`), RAC_TRUE to continue.
 */
typedef rac_bool_t (*rac_http_download_progress_fn)(uint64_t bytes_written, uint64_t total_bytes,
                                                    void* user_data);

// =============================================================================
// API
// =============================================================================

/**
 * @brief Synchronous download. Blocks until done, failed, or cancelled.
 *
 * On success (`RAC_HTTP_DL_OK`), the destination file is closed and
 * contains the full payload (or the merged payload when resuming).
 * Progress callback will have fired at least once (with 100% done).
 *
 * On any non-OK return:
 *   - the destination file MAY still exist with partial contents —
 *     the caller is responsible for deciding whether to delete it
 *     (matches the existing Kotlin semantics)
 *   - `*out_http_status` (when non-null) is set to the last server
 *     response code we saw, or 0 for pre-response failures.
 *
 * @param req                Request descriptor. `url` and
 *                           `destination_path` must be non-NULL.
 * @param progress_cb        Progress callback (can be NULL to
 *                           disable progress reporting).
 * @param progress_user_data Opaque passed to `progress_cb`.
 * @param out_http_status    Out: server response code (optional).
 */
RAC_API rac_http_download_status_t rac_http_download_execute(
    const rac_http_download_request_t* req, rac_http_download_progress_fn progress_cb,
    void* progress_user_data, int32_t* out_http_status);

#ifdef __cplusplus
}
#endif

#endif  // RAC_INFRASTRUCTURE_HTTP_RAC_HTTP_DOWNLOAD_H
