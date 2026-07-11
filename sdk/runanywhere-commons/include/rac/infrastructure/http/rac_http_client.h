/**
 * @file rac_http_client.h
 * @brief Platform-routed HTTP client C ABI.
 *
 * Canonical request/response structs and public entry points for HTTP
 * operations needed by commons. The actual network execution belongs
 * to the registered platform transport adapter (OkHttp, URLSession,
 * fetch, dart:io, etc.) installed via `rac_http_transport_register`.
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
 * been removed from the build. New code should use this ABI for
 * request semantics, response mapping, and streaming download routing,
 * while platform SDKs provide the HTTP execution adapter.
 */

#ifndef RAC_INFRASTRUCTURE_HTTP_RAC_HTTP_CLIENT_H
#define RAC_INFRASTRUCTURE_HTTP_RAC_HTTP_CLIENT_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// TYPES
// =============================================================================

/**
 * @brief Opaque handle preserving the create/destroy ABI.
 * Instances are NOT thread-safe; create one per worker thread.
 */
typedef struct rac_http_client rac_http_client_t;

/**
 * @brief Single HTTP header (key + value, both NUL-terminated).
 *
 * The caller owns the strings for the lifetime of the request
 * struct. Adapters must copy anything they need after the call
 * returns.
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
 * `timeout_ms == 0` means "no timeout".
 *
 * `follow_redirects` is mandatory transport policy. Platform adapters
 * must return the original 3xx response when it is `RAC_FALSE`; this is
 * required for credential-bearing requests so headers and request bodies
 * cannot be replayed to another origin. `RAC_TRUE` enables the platform
 * transport's bounded redirect handling.
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
 * `redirected_url` is non-NULL only when the platform transport
 * actually followed one or more 3xx hops; it is the final absolute URL
 * after hops (owned by the response struct). It remains NULL when redirects
 * are disabled and the original 3xx response is returned to the caller.
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
 * cancel the transfer; adapters surface this as
 * `RAC_ERROR_CANCELLED`.
 */
typedef rac_bool_t (*rac_http_body_chunk_fn)(const uint8_t* chunk, size_t chunk_len,
                                             uint64_t total_written, uint64_t content_length,
                                             void* user_data);

// =============================================================================
// LIFECYCLE
// =============================================================================

/**
 * @brief Create a client instance. The handle preserves the stable ABI
 * and routes requests through the registered transport adapter.
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
 * The registered adapter receives `resume_from_byte` and must attach a
 * correctly-formed `Range: bytes=N-` request. If the server returns
 * 200 instead of 206, the caller can detect this via
 * `out_resp_meta->status` and truncate its destination file before
 * writing the new bytes.
 */
RAC_API rac_result_t rac_http_request_resume(rac_http_client_t* c, const rac_http_request_t* req,
                                             uint64_t resume_from_byte, rac_http_body_chunk_fn cb,
                                             void* user_data, rac_http_response_t* out_resp_meta);

/**
 * @brief Free a response struct. NULL-safe. Frees `body_bytes`,
 * every `headers[i].name` / `headers[i].value`, the outer `headers`
 * array, and `redirected_url`. Does NOT free the struct itself
 * (callers typically stack-allocate).
 */
RAC_API void rac_http_response_free(rac_http_response_t* resp);

// =============================================================================
// REQUEST OPTIONS — UPSERT MODE
// =============================================================================

/**
 * @brief Configures a request for Supabase-style upsert mode.
 *
 * When the request is later submitted via `rac_http_request_send`,
 * `rac_http_request_stream`, or `rac_http_request_resume`, the HTTP
 * client will transparently:
 *   - append `?on_conflict=<on_conflict_field>` (or
 *     `&on_conflict=<on_conflict_field>` if the URL already carries a
 *     query string) to the request URL, and
 *   - emit the header
 *     `Prefer: resolution=merge-duplicates,return=representation`
 *     in addition to any headers already attached to the request.
 *
 * This lets platform SDKs route Supabase device-registration upserts
 * through the standard `rac_http_request_*` ABI without hard-coding the
 * Supabase wire protocol on each platform. Pair with the SDK's
 * higher-level error handling to treat HTTP 409 as a benign "already
 * registered" outcome where appropriate.
 *
 * `on_conflict_field` is copied internally; the caller may free the
 * string immediately after this call returns. Passing
 * `on_conflict_field == NULL` clears any previously-set upsert mode for
 * this request pointer.
 *
 * The flag is keyed by the `rac_http_request_t*` pointer for the
 * duration of one dispatch — the next `rac_http_request_send/stream/
 * resume` consumes (and clears) it. Re-arm before each request if
 * upsert behavior is required for multiple submissions of the same
 * struct.
 *
 * @param req Non-NULL request descriptor.
 * @param on_conflict_field Column name used as the conflict key
 *        (e.g. "device_id"); may be NULL to disable upsert mode.
 * @return RAC_SUCCESS on success, RAC_ERROR_INVALID_ARGUMENT if
 *         `req == NULL`, RAC_ERROR_OUT_OF_MEMORY on allocation failure.
 */
RAC_API rac_result_t rac_http_request_set_upsert_mode(rac_http_request_t* req,
                                                      const char* on_conflict_field);

// =============================================================================
// CANONICAL DEFAULT HEADERS
// =============================================================================

/**
 * @brief Returns commons' canonical default header list.
 *
 * Mirrors the per-SDK `defaultHeaders` block (Swift's
 * `HTTPClientAdapter.defaultHeaders`, Kotlin's CppBridgeTelemetry, etc.) so
 * every transport converges on the same wire shape:
 *
 *   - "X-SDK-Client": "RunAnywhereSDK"
 *   - "X-SDK-Version": rac_get_version().string
 *   - "Content-Type":  "application/json"
 *   - "Accept":        "application/json"
 *
 * The "X-Platform" header is intentionally NOT included — its value
 * ("ios" / "macos" / "android" / "jvm" / "web") is platform-specific and
 * must be supplied per-request by the calling SDK.
 *
 * The returned pointer is to a static array owned by commons; do NOT free
 * it. Multiple calls return the same pointer (suitable for pointer-equality
 * checks in tests). Both header strings are statically allocated with
 * static-storage-duration lifetimes.
 *
 * @param out_kvs   Receives a pointer to the static `rac_http_header_kv_t`
 *                  array. Must be non-NULL.
 * @param out_count Receives the number of entries in the array. Must be
 *                  non-NULL.
 * @return RAC_SUCCESS on success, RAC_ERROR_INVALID_ARGUMENT if either
 *         out-pointer is NULL.
 */
RAC_API rac_result_t rac_http_default_headers(const rac_http_header_kv_t** out_kvs,
                                              size_t* out_count);

// =============================================================================
// HUGGING FACE AUTH
// =============================================================================

/**
 * @brief Sets the process-wide Hugging Face token used to authenticate
 *        gated/private-repo requests (model downloads, HEAD size preflight,
 *        resumable transfers, and the HF Hub tree API used by repo
 *        registration).
 *
 * When set, the dispatch layer attaches `Authorization: Bearer <token>`
 * ONLY to https requests whose host is exactly `huggingface.co` or `hf.co`
 * (never subdomains/CDN hosts) and never overrides a caller-supplied
 * Authorization header. The token is never logged.
 *
 * When unset, the `HF_TOKEN` environment variable (captured on first use)
 * acts as the fallback, so a plain env var works with no call-site change.
 * Passing an empty string clears the token and disables the env fallback
 * (public no-auth behavior); passing NULL resets to the default
 * env-fallback state. Thread-safe; subsequent requests pick up the new
 * value.
 */
RAC_API void rac_http_hf_token_set(const char* token);

// =============================================================================
// RESULT CODES
// =============================================================================
// Consumers only need to check against RAC_SUCCESS; the other
// result codes come from rac/core/rac_error.h. For convenience:
//
//   RAC_SUCCESS                     — transfer completed (check .status
//                                     for HTTP-level errors)
//   RAC_ERROR_INVALID_ARGUMENT      — bad pointer / URL / method
//   RAC_ERROR_OUT_OF_MEMORY         — allocation failure
//   RAC_ERROR_NETWORK_ERROR         — DNS / connect / TLS failure
//   RAC_ERROR_TIMEOUT               — timeout_ms exceeded
//   RAC_ERROR_CANCELLED             — chunk callback returned RAC_FALSE
//   RAC_ERROR_FEATURE_NOT_AVAILABLE — no platform transport registered
//   RAC_ERROR_INTERNAL              — adapter internal error
// =============================================================================

#ifdef __cplusplus
}
#endif

#endif  // RAC_INFRASTRUCTURE_HTTP_RAC_HTTP_CLIENT_H
