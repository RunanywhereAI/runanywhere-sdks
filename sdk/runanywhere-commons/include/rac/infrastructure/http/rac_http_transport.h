/**
 * @file rac_http_transport.h
 * @brief Platform HTTP transport vtable (v2 close-out Phase H2).
 *
 * Cross-platform HTTP routing layer inspired by Realm Core / Mapbox GL
 * Native: the C++ core defines a pure-C vtable, and each platform SDK
 * (Swift URLSession, Kotlin OkHttp, Web fetch, Flutter dart:io,
 * RN fetch/JSI) registers a thin adapter that routes native HTTP
 * requests through that platform's own stack.
 *
 * Follows the same convention as `rac/core/rac_platform_adapter.h` —
 * the SDK layer provides the callbacks, the C++ core delegates.
 *
 * When an adapter is registered, every call into the `rac_http_client_*`
 * C ABI (`rac_http_request_send`, `_stream`, `_resume`) is routed to the
 * registered adapter instead of libcurl. When no adapter is registered,
 * the default libcurl implementation handles the request (current
 * behavior, backward-compatible).
 *
 * Cancellation follows the same rule as the underlying HTTP client:
 * streaming / resume transfers are cancelled by returning `RAC_FALSE`
 * from the chunk callback (no separate cancel-token API).
 *
 * Threading: the registration API is guarded by an internal mutex.
 * Adapter callbacks may be invoked from any thread — implementations
 * must be thread-safe. The `rac_http_request_t` passed to a callback
 * is owned by the caller and valid for the duration of the call only;
 * implementations must copy any strings / byte buffers they need to
 * retain.
 */

#ifndef RAC_INFRASTRUCTURE_HTTP_RAC_HTTP_TRANSPORT_H
#define RAC_INFRASTRUCTURE_HTTP_RAC_HTTP_TRANSPORT_H

#include <stdint.h>

#include "rac/core/rac_types.h"
#include "rac/infrastructure/http/rac_http_client.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// VTABLE
// =============================================================================

/**
 * @brief Platform HTTP transport vtable.
 *
 * Adapters implement these function pointers to route HTTP through their
 * native stack. All fields except `request_send` are optional — set them
 * to NULL to fall back to libcurl for that capability.
 *
 * Return codes match the `rac_http_request_*` contract:
 *   RAC_SUCCESS on any HTTP response (check `out_resp->status`),
 *   RAC_ERROR_NETWORK_ERROR on transport failure,
 *   RAC_ERROR_TIMEOUT on timeout,
 *   RAC_ERROR_CANCELLED on chunk-callback cancel,
 *   RAC_ERROR_INVALID_ARGUMENT / RAC_ERROR_OUT_OF_MEMORY as usual.
 */
typedef struct rac_http_transport_ops {
    /**
     * Execute a synchronous request. Fills `*out_resp` on success.
     *
     * Ownership: `out_resp->body_bytes`, `out_resp->headers`, and
     * `out_resp->redirected_url` must be heap-allocated by the adapter
     * and are freed by the caller via `rac_http_response_free(out_resp)`.
     * Use `malloc`/`strdup`-compatible allocators (same contract as the
     * libcurl default).
     *
     * Required; must not be NULL.
     */
    rac_result_t (*request_send)(void* user_data, const rac_http_request_t* req,
                                 rac_http_response_t* out_resp);

    /**
     * Stream the response body through `cb` as chunks arrive. Populates
     * `*out_resp_meta` with status / headers only (body_bytes stays NULL).
     *
     * The callback returning `RAC_FALSE` cancels the transfer; adapters
     * must surface this as `RAC_ERROR_CANCELLED`.
     *
     * Optional — when NULL the router falls back to libcurl for
     * streaming calls.
     */
    rac_result_t (*request_stream)(void* user_data, const rac_http_request_t* req,
                                   rac_http_body_chunk_fn cb, void* cb_user_data,
                                   rac_http_response_t* out_resp_meta);

    /**
     * Stream a resumable download from `resume_from_byte` using
     * `Range: bytes=N-`. Semantically identical to `request_stream`,
     * except the adapter must attach the `Range` header itself.
     *
     * Optional — when NULL the router falls back to libcurl for resume
     * calls.
     */
    rac_result_t (*request_resume)(void* user_data, const rac_http_request_t* req,
                                   uint64_t resume_from_byte, rac_http_body_chunk_fn cb,
                                   void* cb_user_data, rac_http_response_t* out_resp_meta);

    /**
     * Called once on registration, before any request is routed through
     * the adapter. Returning non-zero unregisters the adapter and surfaces
     * the error to `rac_http_transport_register`.
     *
     * Optional — may be NULL.
     */
    rac_result_t (*init)(void* user_data);

    /**
     * Called when the adapter is replaced (another `_register` call) or
     * unregistered (register with NULL ops). The adapter owns
     * `user_data` and is responsible for releasing it here.
     *
     * Optional — may be NULL.
     */
    void (*destroy)(void* user_data);
} rac_http_transport_ops_t;

// =============================================================================
// REGISTRATION
// =============================================================================

/**
 * @brief Register a platform HTTP transport.
 *
 * Installs `ops` / `user_data` as the active transport. Subsequent
 * `rac_http_request_*` calls are routed through the adapter instead of
 * libcurl. A previously-registered adapter's `destroy` callback is
 * invoked (if any) before the new one is installed.
 *
 * Pass `ops == NULL` to unregister the current adapter and fall back
 * to the libcurl default.
 *
 * Should be called before the first HTTP request for reliable
 * ordering. The `ops` struct must remain valid for the lifetime of
 * the registration; adapters typically use a static/global ops struct.
 *
 * @param ops        Vtable pointer (NULL unregisters).
 * @param user_data  Opaque context passed to every callback
 *                   (and freed via `ops->destroy` at the end).
 * @return RAC_SUCCESS on success; an error from `ops->init` if the
 *         adapter failed to initialize (in which case nothing is
 *         registered).
 */
RAC_API rac_result_t rac_http_transport_register(const rac_http_transport_ops_t* ops,
                                                 void* user_data);

/**
 * @brief Query whether a platform HTTP transport is currently registered.
 *
 * @return RAC_TRUE if an adapter is installed, RAC_FALSE if the router
 *         is using the libcurl default.
 */
RAC_API rac_bool_t rac_http_transport_is_registered(void);

#ifdef __cplusplus
}
#endif

#endif  // RAC_INFRASTRUCTURE_HTTP_RAC_HTTP_TRANSPORT_H
