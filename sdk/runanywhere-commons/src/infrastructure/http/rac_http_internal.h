/**
 * @file rac_http_internal.h
 * @brief Internal C++ HTTP facade used by every commons component
 *        that needs HTTP (v2 close-out Phase H, Stage 2).
 *
 * Internal C++ facade. Always routes through the registered
 * `rac_http_transport_ops_t` adapter if present, else libcurl. Used by
 * all internal commons components that need HTTP (download
 * orchestrator, diffusion tokenizer, JNI bridges).
 *
 * Stage 2 of the HTTP refactor generalises the pre-existing
 * telemetry-delegate pattern into a single entry point. Callers no
 * longer touch `rac_http_client_create` / `rac_http_client_destroy`
 * lifecycle nor the async platform adapter `rac_http_download` —
 * everything funnels through `rac::http::execute` (blocking
 * request/response) or `rac::http::execute_stream` (streaming
 * download with file I/O + progress + cancel + optional SHA-256).
 *
 * Stages 3-5 of the plan eventually delete libcurl; this stage
 * preserves it as the fallback path so behaviour is unchanged.
 *
 * NOT part of the public C ABI. C++-only header, no `extern "C"` —
 * callers outside commons keep using the stable
 * `rac/infrastructure/http/rac_http_client.h` C surface.
 */

#pragma once

#include <cstdint>

#include "rac/core/rac_types.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/http/rac_http_download.h"

namespace rac {
namespace http {

/**
 * @brief Blocking HTTP request/response.
 *
 * Thin C++ wrapper around the standard
 * `rac_http_client_create` + `rac_http_request_send` +
 * `rac_http_client_destroy` triple. The send path already consults
 * the platform-transport registry (`rac_http_transport_ops_t`) so
 * this facade inherits that routing for free; when no adapter is
 * registered the libcurl default runs.
 *
 * On RAC_SUCCESS the response body/headers/redirected_url are owned
 * by `out_resp` — the caller MUST release them via
 * `rac_http_response_free(&out_resp)` (same ownership contract as
 * the underlying C ABI).
 *
 * @param req      Request descriptor (as in rac_http_client.h).
 * @param out_resp Response out-param; populated on success.
 * @return         RAC_SUCCESS on any HTTP response (caller checks
 *                 `out_resp.status`), or RAC_ERROR_* from the
 *                 transport layer.
 */
rac_result_t execute(const rac_http_request_t& req, rac_http_response_t& out_resp);

/**
 * @brief Blocking streaming download: GETs `req->url` and writes the
 * body to `req->destination_path`, optionally resuming from
 * `req->resume_from_byte` and verifying an expected SHA-256 hash.
 *
 * Thin wrapper around `rac_http_download_execute`, which already:
 *   - Creates & destroys an internal `rac_http_client_t` for the
 *     duration of the transfer.
 *   - Opens the destination file (append when resuming, truncate
 *     otherwise; creates parent directories as needed).
 *   - Streams via `rac_http_request_stream` / `rac_http_request_resume`
 *     — both of which route through the platform transport vtable
 *     when registered, else fall back to libcurl.
 *   - Hashes on the wire (no second pass over the file) when a
 *     checksum is supplied.
 *   - Maps transport / filesystem errors to the
 *     `rac_http_download_status_t` enum expected by the Kotlin /
 *     orchestrator consumers.
 *
 * Progress callback returning `RAC_FALSE` cancels the transfer
 * (same contract as `rac_http_download_execute`).
 *
 * @param req                Download descriptor (url, destination,
 *                           timeout, resume offset, expected sha).
 * @param progress_cb        Optional progress callback (may be NULL).
 * @param progress_user_data Opaque passed to progress callback.
 * @param out_http_status    Optional out-param for server response
 *                           code (may be NULL).
 * @return                   RAC_HTTP_DL_OK on success, or a mapped
 *                           status describing the failure mode.
 */
rac_http_download_status_t execute_stream(const rac_http_download_request_t& req,
                                          rac_http_download_progress_fn progress_cb,
                                          void* progress_user_data, int32_t* out_http_status);

}  // namespace http
}  // namespace rac
