/**
 * @file rac_http_upsert_mode.h
 * @brief Internal helpers for the Supabase-style "upsert mode" request
 *        flag set via `rac_http_request_set_upsert_mode`.
 *
 * The public C ABI (in `rac_http_client.h`) lets callers tag a
 * `rac_http_request_t*` as an UPSERT before submitting it. The actual
 * URL / header transformation lives here so that every dispatch site
 * (`rac_http_client_default.cpp` for native targets,
 * `rac_http_client_emscripten.cpp` for WASM) can apply it uniformly.
 *
 * Why a side table? — `rac_http_request_t` is a flat ABI-stable C
 * struct already in use by every SDK. Adding fields is breaking;
 * keying upsert state by the `rac_http_request_t*` pointer keeps the
 * struct untouched while still letting the dispatch layer pull the
 * config back out before calling the registered platform transport.
 *
 * NOT part of the public C ABI. C++-only.
 */

#pragma once

#include <string>

#include "rac/core/rac_types.h"
#include "rac/infrastructure/http/rac_http_client.h"

namespace rac::http {

/**
 * @brief Snapshot of upsert-mode state for a single dispatch.
 *
 * `engaged == true` means a previous call to
 * `rac_http_request_set_upsert_mode` armed this request. `transformed_url`
 * is the URL after the `on_conflict=<field>` query parameter has been
 * appended. `prefer_header_value` is the literal value to send under the
 * `Prefer:` header.
 *
 * When `engaged == false` the other fields are empty and the dispatch
 * site should pass the request through unchanged.
 */
struct UpsertTransform {
    bool engaged = false;
    std::string transformed_url;
    std::string prefer_header_value;
};

/**
 * @brief Pulls upsert state for `req` (if any) and clears the entry.
 *
 * Returns a `UpsertTransform` describing the rewrite to apply for this
 * dispatch. Calling this consumes the entry — a second call for the
 * same `req*` returns `engaged = false`. Callers that need to re-issue
 * the same request must re-arm with `rac_http_request_set_upsert_mode`.
 *
 * Thread-safe: backed by a mutex-guarded global map.
 */
UpsertTransform consume_upsert_transform(const rac_http_request_t* req);

}  // namespace rac::http
