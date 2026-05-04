/**
 * @file rac_http_client.h
 * @brief Native HTTP client C ABI (v2 close-out Phase H).
 *
 * Opaque handle around a libcurl easy handle (see
 * `src/infrastructure/http/rac_http_client_curl.cpp`). Replaces the
 * per-SDK hand-rolled HTTP transport (HttpURLConnection in Kotlin,
 * URLSession in Swift, fetch/axios in RN/Web, http in Flutter) with a
 * single canonical implementation shared via this C ABI.
 *
 * Scope:
 *   - blocking request/response (`rac_http_request_send`)
 *   - streaming body delivered via per-chunk callback
 *     (`rac_http_request_stream`)
 *   - byte-range resume
 *     (`rac_http_request_resume` — wraps `Range: bytes=N-`)
 *   - redirects, custom headers, configurable timeouts
 *   - cancellation via chunk-callback return value
 *
 * The older executor-plugin ABI under `infrastructure/network` has
 * been removed from the build. New code must use this curl-backed ABI
 * for request/response and streaming download transport.
 */

#ifndef RAC_INFRASTRUCTURE_HTTP_RAC_HTTP_CLIENT_H
#define RAC_INFRASTRUCTURE_HTTP_RAC_HTTP_CLIENT_H

#include <stddef.h>
#include <stdint.h>

#include "rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// TYPES
// =============================================================================

/**
 * @brief Opaque handle. One handle == one libcurl easy handle.
 * Instances are NOT thread-safe; create one per worker thread.
 */
typedef struct rac_http_client rac_http_client_t;

/**
 * @brief Single HTTP header (key + value, both NUL-terminated).
 *
 * The caller owns the strings for the lifetime of the request
 * struct; the implementation copies them into libcurl's slist before
 * firing the request.
 */
typedef struct {
    const char* name;
    const char* value;
} rac_http_header_kv_t;

/**
 * @brief Request descriptor.
 *
 * `method` is uppercase ASCII ("GET" / "POST" / "PUT" / "DELETE" /
 * "PATCH" / "HEAD"). `url` must be a full absolute URL (http:// or
 * https://). `headers` can be NULL when `header_count == 0`.
 *
 * `body_bytes` / `body_len` are ignored for GET/HEAD. Set
 * `expected_checksum_hex` is advisory: the HTTP client does NOT
 * verify it — resumable / streaming downloads need to checksum on
 * the caller side where the bytes land on disk. The field is carried
 * here so a single descriptor can travel end-to-end through the
 * download manager. NULL = no checksum check.
 *
 * `timeout_ms == 0` means "no timeout" (libcurl default).
 * `follow_redirects == RAC_TRUE` follows 3xx up to 10 hops.
 */
typedef struct {
    const char* method;
    const char* url;

    const rac_http_header_kv_t* headers;
    size_t header_count;

    const uint8_t* body_bytes;
    size_t body_len;

    int32_t timeout_ms;
    rac_bool_t follow_redirects;

    const char* expected_checksum_hex;
} rac_http_request_t;

/**
 * @brief Response descriptor.
 *
 * `body_bytes` is NULL for streaming calls
 * (`rac_http_request_stream`, `rac_http_request_resume`); they
 * deliver the body through the chunk callback. For
 * `rac_http_request_send` the body is a heap-allocated buffer of
 * length `body_len`.
 *
 * `headers` is an allocated array of `header_count` items; both the
 * outer array and the `name`/`value` strings live until the caller
 * invokes `rac_http_response_free(resp)`.
 *
 * `redirected_url` is non-NULL only when the server returned a 3xx
 * and `follow_redirects == RAC_TRUE`; it is the final absolute URL
 * after hops (owned by the response struct).
 *
 * `elapsed_ms` is total wall-clock time from connect to last byte.
 */
typedef struct {
    int32_t status;

    rac_http_header_kv_t* headers;
    size_t header_count;

    uint8_t* body_bytes;
    size_t body_len;

    char* redirected_url;

    uint64_t elapsed_ms;
} rac_http_response_t;

/**
 * @brief Streaming body callback.
 *
 * Called 0..N times as bytes arrive on the wire. Total bytes
 * delivered across all calls equals `total_written` on the final
 * invocation. `content_length` is the server-declared length (0 if
 * the server did not send `Content-Length`). Return `RAC_FALSE` to
 * cancel the transfer — libcurl aborts the connection and
 * `rac_http_request_stream` returns a non-zero status.
 */
typedef rac_bool_t (*rac_http_body_chunk_fn)(const uint8_t* chunk, size_t chunk_len,
                                             uint64_t total_written, uint64_t content_length,
                                             void* user_data);

// =============================================================================
// LIFECYCLE
// =============================================================================

/**
 * @brief Create a client instance. Each instance holds a single
 * libcurl easy handle; it is NOT thread-safe. Use one per worker.
 *
 * @param out Handle out parameter (NULL on failure).
 * @return RAC_SUCCESS on success, RAC_ERROR_OUT_OF_MEMORY /
 *         RAC_ERROR_INTERNAL on failure.
 */
RAC_API rac_result_t rac_http_client_create(rac_http_client_t** out);

/**
 * @brief Destroy a client instance. NULL-safe.
 */
RAC_API void rac_http_client_destroy(rac_http_client_t* c);

// =============================================================================
// REQUESTS
// =============================================================================

/**
 * @brief Send a blocking request, buffer full body into `out_resp`.
 *
 * On success the response body lives in `out_resp->body_bytes` (size
 * `body_len`). The caller MUST call `rac_http_response_free(out_resp)`
 * to release the body + headers + redirected_url allocations.
 *
 * @return RAC_SUCCESS on any HTTP response (even 4xx/5xx — check
 *         `out_resp->status`). Network / connect / TLS errors return
 *         RAC_ERROR_NETWORK_ERROR. Timeout returns RAC_ERROR_TIMEOUT.
 *         Cancellation only applies to the streaming variants.
 */
RAC_API rac_result_t rac_http_request_send(rac_http_client_t* c, const rac_http_request_t* req,
                                           rac_http_response_t* out_resp);

/**
 * @brief Stream body through `cb` as chunks arrive. The response
 * struct is populated with status/headers only — `body_bytes` stays
 * NULL; the body never lands in memory.
 *
 * Return `RAC_FALSE` from `cb` to cancel the transfer — the
 * connection is aborted and RAC_ERROR_CANCELLED is returned.
 */
RAC_API rac_result_t rac_http_request_stream(rac_http_client_t* c, const rac_http_request_t* req,
                                             rac_http_body_chunk_fn cb, void* user_data,
                                             rac_http_response_t* out_resp_meta);

/**
 * @brief Resume a download from `resume_from_byte` using
 * `Range: bytes=N-`. Semantically identical to
 * `rac_http_request_stream`, except the caller must already have the
 * first `resume_from_byte` bytes on disk.
 *
 * The implementation sets `CURLOPT_RESUME_FROM_LARGE` which appends
 * a correctly-formed `Range` header. If the server returns 200
 * instead of 206, the caller can detect this via
 * `out_resp_meta->status` and truncate its destination file before
 * writing the new bytes.
 */
RAC_API rac_result_t rac_http_request_resume(rac_http_client_t* c, const rac_http_request_t* req,
                                             uint64_t resume_from_byte,
                                             rac_http_body_chunk_fn cb, void* user_data,
                                             rac_http_response_t* out_resp_meta);

/**
 * @brief Free a response struct. NULL-safe. Frees `body_bytes`,
 * every `headers[i].name` / `headers[i].value`, the outer `headers`
 * array, and `redirected_url`. Does NOT free the struct itself
 * (callers typically stack-allocate).
 */
RAC_API void rac_http_response_free(rac_http_response_t* resp);

// =============================================================================
// RESULT CODES
// =============================================================================
// Phase H consumers only need to check against RAC_SUCCESS; the other
// result codes come from rac/core/rac_error.h. For convenience:
//
//   RAC_SUCCESS                     — transfer completed (check .status
//                                     for HTTP-level errors)
//   RAC_ERROR_INVALID_ARGUMENT      — bad pointer / URL / method
//   RAC_ERROR_OUT_OF_MEMORY         — allocation failure
//   RAC_ERROR_NETWORK_ERROR         — DNS / connect / TLS failure
//   RAC_ERROR_TIMEOUT               — timeout_ms exceeded
//   RAC_ERROR_CANCELLED             — chunk callback returned RAC_FALSE
//   RAC_ERROR_INTERNAL              — libcurl internal error
// =============================================================================

#ifdef __cplusplus
}
#endif

#endif  // RAC_INFRASTRUCTURE_HTTP_RAC_HTTP_CLIENT_H
