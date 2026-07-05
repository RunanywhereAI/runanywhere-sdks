/**
 * @file rac_http_client_emscripten.cpp
 * @brief Emscripten Fetch-backed HTTP transport adapter.
 *
 * The Web implementation registers
 * itself through the platform HTTP transport vtable declared in
 * `include/rac/infrastructure/http/rac_http_transport.h`.
 *
 * The public `rac_http_request_*` entry points consult the transport
 * registry and dispatch to whichever Web adapter is installed. Doing
 * it that way means the WASM build goes through the same routing
 * pattern used by the Swift URLSession / Kotlin OkHttp / Flutter
 * dart:io / RN fetch adapters.
 *
 * The actual emscripten_fetch() logic below is unchanged —
 * only the wiring is different. See `rac_http_transport.h` for the
 * ownership / threading contract every adapter must satisfy:
 *   - callbacks can be invoked from any thread (we block on
 *     EMSCRIPTEN_FETCH_SYNCHRONOUS so "any thread" means the worker
 *     pthread that issued the request),
 *   - strings/bytes handed to us are caller-owned,
 *   - out_resp fields must be heap-allocated with malloc/strdup-
 *     compatible allocators so the shared `rac_http_response_free`
 *     frees them correctly.
 *
 * See `include/rac/infrastructure/http/rac_http_client.h` for the
 * original C ABI contract. This file is compiled into `rac_commons`
 * ONLY when `CMAKE_SYSTEM_NAME == Emscripten` (see `CMakeLists.txt`).
 *
 * Threading / synchronicity:
 *   - The RAC HTTP client API is synchronous (send/stream/resume all
 *     block until the response is fully delivered or errored).
 *   - Emscripten's `emscripten_fetch` is natively async; synchronous
 *     operation requires either `-sASYNCIFY` (JS-side event-loop
 *     re-entry) or `-sPROXY_TO_PTHREAD` + worker threads.
 *   - We use `EMSCRIPTEN_FETCH_SYNCHRONOUS`, which under the hood
 *     relies on one of the two mechanisms above. The link flags in
 *     `sdk/runanywhere-web/wasm/CMakeLists.txt` include `-sFETCH=1`
 *     and Asyncify (implicit via JSPI when WebGPU is on, explicit via
 *     `-sASYNCIFY=1` otherwise — see the emscripten branch there).
 *
 * Emscripten Fetch adapter limitations:
 *   - No cookie jar (the browser's own cookies are used per CORS
 *     rules; the SDK never sees them).
 *   - No per-request redirect toggle: `fetch()` always follows
 *     redirects per `redirect: "follow"` (the default).
 *   - `total_time` is derived from a wall-clock measurement around the
 *     blocking `emscripten_fetch` call.
 *   - Streaming body callbacks are fired once with the whole buffer
 *     (the Fetch API's `ReadableStream` requires async JS glue that's
 *     out of scope for the MVP). Download byte counts remain correct;
 *     only the progress granularity is coarser than chunked native
 *     adapters.
 *   - Response headers are parsed from
 *     `emscripten_fetch_get_response_headers_length` /
 *     `..._get_response_headers`.
 */

#include "rac_http_transport_ref.h"
#include "rac_http_hf_auth.h"
#include "rac_http_upsert_mode.h"

#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <emscripten/emscripten.h>
#include <emscripten/fetch.h>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/http/rac_http_transport.h"

namespace {

constexpr const char* kTag = "rac_http_client_emscripten";

// =============================================================================
// Helpers
// =============================================================================

bool method_is_head(const char* m) {
    return m != nullptr && std::strcmp(m, "HEAD") == 0;
}

bool ascii_equals_ignore_case(const char* lhs, const char* rhs) {
    if (!lhs || !rhs) {
        return false;
    }
    while (*lhs != '\0' && *rhs != '\0') {
        char a = *lhs++;
        char b = *rhs++;
        if (a >= 'A' && a <= 'Z') {
            a = static_cast<char>(a - 'A' + 'a');
        }
        if (b >= 'A' && b <= 'Z') {
            b = static_cast<char>(b - 'A' + 'a');
        }
        if (a != b) {
            return false;
        }
    }
    return *lhs == '\0' && *rhs == '\0';
}

bool has_authorization_header(const rac_http_request_t* req) {
    if (!req || !req->headers) {
        return false;
    }
    for (size_t i = 0; i < req->header_count; ++i) {
        if (ascii_equals_ignore_case(req->headers[i].name, "Authorization")) {
            return true;
        }
    }
    return false;
}

/// Copy the user's method + headers into arrays owned by a helper
/// struct so the `emscripten_fetch_attr_t` pointers remain valid for
/// the lifetime of the blocking call.
struct fetch_request_ctx {
    std::vector<std::string> header_storage;
    std::vector<const char*> header_ptrs;
    std::string body_copy;
    std::string range_header_storage;

    void build_headers(const rac_http_request_t* req, uint64_t resume_from_byte) {
        // Each header becomes two entries (name, value), followed by
        // a NULL terminator as required by Emscripten Fetch.
        header_storage.reserve(req->header_count * 2 + 2);
        for (size_t i = 0; i < req->header_count; ++i) {
            const auto& h = req->headers[i];
            if (!h.name || !h.value) {
                continue;
            }
            header_storage.emplace_back(h.name);
            header_storage.emplace_back(h.value);
        }
        if (resume_from_byte > 0) {
            header_storage.emplace_back("Range");
            range_header_storage = "bytes=" + std::to_string(resume_from_byte) + "-";
            header_storage.emplace_back(range_header_storage);
        }
        header_ptrs.reserve(header_storage.size() + 1);
        for (const auto& s : header_storage) {
            header_ptrs.push_back(s.c_str());
        }
        header_ptrs.push_back(nullptr);  // Emscripten expects a NULL terminator.
    }
};

/// Parse the raw "Name: Value\r\nName2: Value2\r\n..." blob returned
/// by emscripten_fetch_get_response_headers into individual kv pairs.
void parse_response_headers(const char* raw, rac_http_response_t* out) {
    if (!raw) {
        return;
    }
    std::vector<std::pair<std::string, std::string>> pairs;
    const char* p = raw;
    while (*p) {
        const char* line_end = std::strstr(p, "\r\n");
        std::string line = line_end ? std::string(p, line_end - p) : std::string(p);
        if (!line.empty()) {
            // Skip status lines ("HTTP/1.1 200 OK") — no ":" before the value.
            auto colon = line.find(':');
            if (colon != std::string::npos && line.rfind("HTTP/", 0) != 0) {
                std::string name = line.substr(0, colon);
                std::string value = line.substr(colon + 1);
                size_t i = 0;
                while (i < value.size() && (value[i] == ' ' || value[i] == '\t')) {
                    ++i;
                }
                value.erase(0, i);
                pairs.emplace_back(std::move(name), std::move(value));
            }
        }
        if (!line_end) {
            break;
        }
        p = line_end + 2;
    }

    if (pairs.empty()) {
        return;
    }
    out->header_count = pairs.size();
    out->headers =
        static_cast<rac_http_header_kv_t*>(std::calloc(pairs.size(), sizeof(rac_http_header_kv_t)));
    if (!out->headers) {
        out->header_count = 0;
        return;
    }
    for (size_t i = 0; i < pairs.size(); ++i) {
        out->headers[i].name = strdup(pairs[i].first.c_str());
        out->headers[i].value = strdup(pairs[i].second.c_str());
    }
}

/// Run a synchronous `emscripten_fetch` and populate `out` with the
/// response body + metadata. `cb`/`user_data` are non-NULL for
/// streaming calls; in that case the body buffer is NOT allocated into
/// `out->body_bytes` and is instead delivered through `cb` in one
/// chunk.
rac_result_t do_fetch(const rac_http_request_t* req, rac_http_response_t* out,
                      rac_http_body_chunk_fn cb, void* user_data, uint64_t resume_from_byte) {
    if (!req || !req->url || !req->method || !out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    emscripten_fetch_attr_t attr;
    emscripten_fetch_attr_init(&attr);

    // Emscripten copies requestMethod into an internal buffer but the
    // field itself is a fixed-size char array — bounds-check.
    std::strncpy(attr.requestMethod, req->method, sizeof(attr.requestMethod) - 1);
    attr.requestMethod[sizeof(attr.requestMethod) - 1] = '\0';

    attr.attributes = EMSCRIPTEN_FETCH_LOAD_TO_MEMORY | EMSCRIPTEN_FETCH_SYNCHRONOUS;
    // HEAD requests should not download a body.
    if (method_is_head(req->method)) {
        attr.attributes |= EMSCRIPTEN_FETCH_NO_DOWNLOAD;
    }

    // Timeout (emscripten expects ms; 0 = no timeout).
    attr.timeoutMSecs = req->timeout_ms > 0 ? static_cast<unsigned long>(req->timeout_ms) : 0;

    // Build headers + optional Range header (resume). The header
    // pointer array must outlive the call, so we stash it on the stack.
    fetch_request_ctx rctx;
    rctx.build_headers(req, resume_from_byte);
    if (!rctx.header_ptrs.empty() && rctx.header_ptrs.front() != nullptr) {
        attr.requestHeaders = rctx.header_ptrs.data();
    }

    // Request body (copy into a stable buffer since Emscripten expects
    // NUL-terminated semantics for `requestData`).
    if (req->body_bytes && req->body_len > 0) {
        rctx.body_copy.assign(reinterpret_cast<const char*>(req->body_bytes), req->body_len);
        attr.requestData = rctx.body_copy.data();
        attr.requestDataSize = rctx.body_copy.size();
    }

    const auto t_start = std::chrono::steady_clock::now();
    emscripten_fetch_t* fetch = emscripten_fetch(&attr, req->url);
    const auto t_end = std::chrono::steady_clock::now();

    if (!fetch) {
        RAC_LOG_ERROR(kTag, "emscripten_fetch returned NULL for url=%s", req->url);
        return RAC_ERROR_NETWORK_ERROR;
    }

    out->status = static_cast<int32_t>(fetch->status);
    out->elapsed_ms = static_cast<uint64_t>(
        std::chrono::duration_cast<std::chrono::milliseconds>(t_end - t_start).count());

    // emscripten_fetch_t does not expose the effective post-redirect URL, so
    // redirected_url stays NULL (already zeroed by the caller) per the C ABI:
    // it must be non-NULL only when a real 3xx hop occurred.

    // Headers.
    size_t hdrs_len = emscripten_fetch_get_response_headers_length(fetch);
    if (hdrs_len > 0) {
        std::string raw(hdrs_len + 1, '\0');
        emscripten_fetch_get_response_headers(fetch, raw.data(), raw.size());
        parse_response_headers(raw.c_str(), out);
    }

    // Body.
    if (cb != nullptr) {
        // Streaming variant — deliver the whole buffer in one callback.
        uint64_t total = fetch->numBytes > 0 ? static_cast<uint64_t>(fetch->numBytes) : 0;
        bool cancelled = false;
        if (fetch->data != nullptr && total > 0) {
            rac_bool_t keep_going = cb(reinterpret_cast<const uint8_t*>(fetch->data),
                                       static_cast<size_t>(total), total, total, user_data);
            if (keep_going == RAC_FALSE) {
                cancelled = true;
            }
        }
        out->body_bytes = nullptr;
        out->body_len = 0;
        // Finished with fetch resources regardless of status.
        const bool http_ok = fetch->status >= 200 && fetch->status < 400;
        emscripten_fetch_close(fetch);
        if (cancelled) {
            return RAC_ERROR_CANCELLED;
        }
        if (!http_ok && fetch->status == 0) {
            return RAC_ERROR_NETWORK_ERROR;
        }
        return RAC_SUCCESS;
    }

    // Buffered variant — copy into out->body_bytes.
    if (fetch->data != nullptr && fetch->numBytes > 0) {
        out->body_len = static_cast<size_t>(fetch->numBytes);
        out->body_bytes = static_cast<uint8_t*>(std::malloc(out->body_len));
        if (!out->body_bytes) {
            out->body_len = 0;
            emscripten_fetch_close(fetch);
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        std::memcpy(out->body_bytes, fetch->data, out->body_len);
    }

    // A status of 0 from emscripten_fetch means the request failed to
    // reach the network at all (CORS, DNS, offline, etc.).
    const bool network_failure = (fetch->status == 0);
    emscripten_fetch_close(fetch);
    if (network_failure) {
        return RAC_ERROR_NETWORK_ERROR;
    }
    return RAC_SUCCESS;
}

// =============================================================================
// Transport vtable ops
//
// These are the thin shims the transport router in
// `rac_http_transport.cpp` calls into. Signature matches
// `rac_http_transport_ops_t` — the leading
// `void* user_data` slot is unused here (the adapter has no state;
// emscripten_fetch is stateless at the handle level).
// =============================================================================

rac_result_t emscripten_request_send(void* /*user_data*/, const rac_http_request_t* req,
                                     rac_http_response_t* out_resp) {
    if (!req || !out_resp) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    std::memset(out_resp, 0, sizeof(*out_resp));
    return do_fetch(req, out_resp, /*cb=*/nullptr, /*user_data=*/nullptr,
                    /*resume_from_byte=*/0);
}

rac_result_t emscripten_request_stream(void* /*user_data*/, const rac_http_request_t* req,
                                       rac_http_body_chunk_fn cb, void* cb_user_data,
                                       rac_http_response_t* out_resp_meta) {
    if (!req || !cb || !out_resp_meta) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    std::memset(out_resp_meta, 0, sizeof(*out_resp_meta));
    return do_fetch(req, out_resp_meta, cb, cb_user_data, /*resume_from_byte=*/0);
}

rac_result_t emscripten_request_resume(void* /*user_data*/, const rac_http_request_t* req,
                                       uint64_t resume_from_byte, rac_http_body_chunk_fn cb,
                                       void* cb_user_data, rac_http_response_t* out_resp_meta) {
    if (!req || !cb || !out_resp_meta) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    std::memset(out_resp_meta, 0, sizeof(*out_resp_meta));
    return do_fetch(req, out_resp_meta, cb, cb_user_data, resume_from_byte);
}

// Static ops struct — must outlive any request (the transport registry
// only stores a pointer), so file-scope storage is the right home.
const rac_http_transport_ops_t kEmscriptenOps = {
    /*.request_send   =*/emscripten_request_send,
    /*.request_stream =*/emscripten_request_stream,
    /*.request_resume =*/emscripten_request_resume,
    /*.init           =*/nullptr,
    /*.destroy        =*/nullptr,
};

// =============================================================================
// JS-side adapter
//
// Instead of the C++ calling `emscripten_fetch` (which then calls JS
// `fetch()` under the hood — one extra hop + ASYNCIFY requirement), the
// JS layer can register its own `fetch()`-backed implementation via
// `rac_http_transport_register_from_js(...)`. JS passes in three
// function-table indices (obtained via `Module.addFunction(fn, sig)`)
// that match the rac_http_transport_ops_t signatures, and we fan them
// out through a trampoline struct stored at file scope.
//
// Advantages:
//   - One less C++ ↔ JS hop per request.
//   - Works without `-sASYNCIFY=1` (the JS side handles its own promise
//     plumbing end-to-end).
//   - JS-side can plug in retry logic, caching, service workers, etc.
//
// Fallback: if JS never calls `rac_http_transport_register_from_js`,
// the existing `rac_http_transport_register_emscripten()` path (above)
// continues to work unchanged.
// =============================================================================

struct JsTransportState {
    // Function-table indices. Emscripten's addFunction installs the
    // JS function at a table slot and returns the index; calling through
    // the resulting function pointer invokes the JS function with the
    // proper argument marshaling (see the sig-string contract in
    // FetchHttpTransport.ts).
    rac_result_t (*request_send)(void*, const rac_http_request_t*, rac_http_response_t*) = nullptr;
    rac_result_t (*request_stream)(void*, const rac_http_request_t*, rac_http_body_chunk_fn, void*,
                                   rac_http_response_t*) = nullptr;
    rac_result_t (*request_resume)(void*, const rac_http_request_t*, uint64_t,
                                   rac_http_body_chunk_fn, void*, rac_http_response_t*) = nullptr;
};

// File-scope so the registered vtable still sees the JS function
// pointers after rac_http_transport_register_from_js returns.
JsTransportState& js_transport_state() {
    static JsTransportState s;
    return s;
}

rac_result_t js_request_send(void* user_data, const rac_http_request_t* req,
                             rac_http_response_t* out_resp) {
    auto& s = js_transport_state();
    if (s.request_send != nullptr) {
        return s.request_send(user_data, req, out_resp);
    }
    // Fallback to the native emscripten_fetch path.
    return emscripten_request_send(user_data, req, out_resp);
}

rac_result_t js_request_stream(void* user_data, const rac_http_request_t* req,
                               rac_http_body_chunk_fn cb, void* cb_user_data,
                               rac_http_response_t* out_resp_meta) {
    auto& s = js_transport_state();
    if (s.request_stream != nullptr) {
        return s.request_stream(user_data, req, cb, cb_user_data, out_resp_meta);
    }
    return emscripten_request_stream(user_data, req, cb, cb_user_data, out_resp_meta);
}

rac_result_t js_request_resume(void* user_data, const rac_http_request_t* req,
                               uint64_t resume_from_byte, rac_http_body_chunk_fn cb,
                               void* cb_user_data, rac_http_response_t* out_resp_meta) {
    auto& s = js_transport_state();
    if (s.request_resume != nullptr) {
        return s.request_resume(user_data, req, resume_from_byte, cb, cb_user_data, out_resp_meta);
    }
    return emscripten_request_resume(user_data, req, resume_from_byte, cb, cb_user_data,
                                     out_resp_meta);
}

const rac_http_transport_ops_t kJsOps = {
    /*.request_send   =*/js_request_send,
    /*.request_stream =*/js_request_stream,
    /*.request_resume =*/js_request_resume,
    /*.init           =*/nullptr,
    /*.destroy        =*/nullptr,
};

}  // namespace

// =============================================================================
// Public registration API — JS calls this once after the WASM module
// loads so every HTTP request routes through the Emscripten Fetch
// adapter. Since this is still the only HTTP implementation in the
// WASM build, this file also exports the public `rac_http_request_*`
// symbols.
// =============================================================================

extern "C" RAC_API rac_result_t rac_http_transport_register_emscripten(void) {
    RAC_LOG_INFO(kTag, "Registering emscripten_fetch HTTP transport");
    return rac_http_transport_register(&kEmscriptenOps, /*user_data=*/nullptr);
}

// =============================================================================
// JS-side registration. Takes three function-table indices
// (obtained from `Module.addFunction(fn, sig)` on the JS side) that match
// `rac_http_transport_ops_t.request_send` / `_stream` / `_resume`. Any of
// them may be null — the corresponding op uses the Emscripten Fetch
// adapter.
//
// The JS side should call this AFTER WASM module load. Registration
// installs the JS-fanout vtable into the transport registry, so public
// HTTP calls dispatch to JS for every subsequent HTTP request. This
// avoids the emscripten_fetch
// ASYNCIFY requirement and lets the JS side plug in retry / caching /
// service-worker routing.
//
// Pass all three pointers as 0 to unregister the JS adapter. The JS
// function-table indices remain owned by the JS side (i.e. JS is
// responsible for the matching `removeFunction`).
// =============================================================================

extern "C" RAC_API rac_result_t rac_http_transport_register_from_js(
    rac_result_t (*request_send_fp)(void*, const rac_http_request_t*, rac_http_response_t*),
    rac_result_t (*request_stream_fp)(void*, const rac_http_request_t*, rac_http_body_chunk_fn,
                                      void*, rac_http_response_t*),
    rac_result_t (*request_resume_fp)(void*, const rac_http_request_t*, uint64_t,
                                      rac_http_body_chunk_fn, void*, rac_http_response_t*)) {
    auto& s = js_transport_state();
    s.request_send = request_send_fp;
    s.request_stream = request_stream_fp;
    s.request_resume = request_resume_fp;

    // If all three were cleared, unregister the JS adapter. The
    // emscripten_fetch adapter remains reachable via
    // rac_http_transport_register_emscripten().
    if (request_send_fp == nullptr && request_stream_fp == nullptr &&
        request_resume_fp == nullptr) {
        RAC_LOG_INFO(kTag, "JS HTTP transport unregistered");
        return rac_http_transport_register(/*ops=*/nullptr, /*user_data=*/nullptr);
    }

    RAC_LOG_INFO(kTag, "Registering JS HTTP transport (send=%s, stream=%s, resume=%s)",
                 request_send_fp ? "JS" : "emscripten_fetch",
                 request_stream_fp ? "JS" : "emscripten_fetch",
                 request_resume_fp ? "JS" : "emscripten_fetch");
    return rac_http_transport_register(&kJsOps, /*user_data=*/nullptr);
}

// =============================================================================
// Opaque handle: downstream code (`rac_http_download.cpp`) treats the
// WASM and native handles the same.
// =============================================================================

struct rac_http_client {
    // Emscripten Fetch is stateless at the handle level; the struct
    // exists solely so the API contract (create/destroy pair) holds.
    int _unused;
};

// =============================================================================
// Public API — routes through the platform transport registry so the
// JS-side trampolines installed via `rac_http_transport_register_from_js`
// take precedence over the built-in emscripten_fetch adapter.
//
// Parity with `rac_http_client_default.cpp` (non-WASM targets): the
// public entry points consult `rac_internal::get_http_transport()`. On
// WASM the emscripten_fetch adapter is registered eagerly (see
// `ra_commons_install_default_transport()` below), so even when the JS
// layer never calls `rac_http_transport_register_from_js`, requests
// still resolve through the emscripten_fetch vtable rather than failing
// with RAC_ERROR_FEATURE_NOT_AVAILABLE.
// =============================================================================

namespace {

/// Mirror of `PreparedRequest` in `rac_http_client_default.cpp` — see
/// `rac_http_upsert_mode.h` for rationale. Both dispatch sites apply the
/// same Supabase-style URL/header rewrite when a request was armed via
/// `rac_http_request_set_upsert_mode` so behaviour is identical across
/// native and WASM targets.
struct PreparedRequest {
    rac_http_request_t effective_request{};
    std::vector<rac_http_header_kv_t> header_storage;
    std::string url_storage;
    std::string prefer_value_storage;
    std::string auth_value_storage;
    bool transformed = false;
};

PreparedRequest prepare_request(const rac_http_request_t* req) {
    PreparedRequest prepared;
    prepared.effective_request = *req;

    auto transform = rac::http::consume_upsert_transform(req);
    if (transform.engaged) {
        prepared.transformed = true;
        prepared.url_storage = std::move(transform.transformed_url);
        prepared.prefer_value_storage = std::move(transform.prefer_header_value);

        prepared.header_storage.reserve(req->header_count + 2);
        for (size_t i = 0; i < req->header_count; ++i) {
            prepared.header_storage.push_back(req->headers[i]);
        }
        prepared.header_storage.push_back(
            rac_http_header_kv_t{"Prefer", prepared.prefer_value_storage.c_str()});

        prepared.effective_request.url = prepared.url_storage.c_str();
        prepared.effective_request.headers = prepared.header_storage.data();
        prepared.effective_request.header_count = prepared.header_storage.size();
    }

    auto bearer = rac::http::hf_bearer_for_url(prepared.effective_request.url,
                                               has_authorization_header(&prepared.effective_request));
    if (!bearer.empty()) {
        if (prepared.header_storage.empty() && req->header_count > 0) {
            prepared.header_storage.reserve(req->header_count + 1);
            for (size_t i = 0; i < req->header_count; ++i) {
                prepared.header_storage.push_back(req->headers[i]);
            }
        }
        prepared.auth_value_storage = std::move(bearer);
        prepared.header_storage.push_back(
            rac_http_header_kv_t{"Authorization", prepared.auth_value_storage.c_str()});
        prepared.effective_request.headers = prepared.header_storage.data();
        prepared.effective_request.header_count = prepared.header_storage.size();
    }
    return prepared;
}

rac_result_t dispatch_send(const rac_http_request_t* req, rac_http_response_t* out_resp) {
    PreparedRequest prepared = prepare_request(req);
    rac_internal::TransportRef transport;
    if (!transport || transport.ops()->request_send == nullptr) {
        return emscripten_request_send(/*user_data=*/nullptr, &prepared.effective_request,
                                       out_resp);
    }
    return transport.ops()->request_send(transport.user_data(), &prepared.effective_request,
                                         out_resp);
}

rac_result_t dispatch_stream(const rac_http_request_t* req, rac_http_body_chunk_fn cb,
                             void* user_data, rac_http_response_t* out_resp_meta) {
    PreparedRequest prepared = prepare_request(req);
    rac_internal::TransportRef transport;
    if (!transport || transport.ops()->request_stream == nullptr) {
        return emscripten_request_stream(/*user_data=*/nullptr, &prepared.effective_request, cb,
                                         user_data, out_resp_meta);
    }
    return transport.ops()->request_stream(transport.user_data(), &prepared.effective_request, cb,
                                           user_data, out_resp_meta);
}

rac_result_t dispatch_resume(const rac_http_request_t* req, uint64_t resume_from_byte,
                             rac_http_body_chunk_fn cb, void* user_data,
                             rac_http_response_t* out_resp_meta) {
    PreparedRequest prepared = prepare_request(req);
    rac_internal::TransportRef transport;
    if (!transport || transport.ops()->request_resume == nullptr) {
        return emscripten_request_resume(/*user_data=*/nullptr, &prepared.effective_request,
                                         resume_from_byte, cb, user_data, out_resp_meta);
    }
    return transport.ops()->request_resume(transport.user_data(), &prepared.effective_request,
                                           resume_from_byte, cb, user_data, out_resp_meta);
}

}  // namespace

extern "C" rac_result_t rac_http_client_create(rac_http_client_t** out) {
    if (!out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *out = static_cast<rac_http_client_t*>(std::calloc(1, sizeof(rac_http_client_t)));
    if (!*out) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    return RAC_SUCCESS;
}

extern "C" void rac_http_client_destroy(rac_http_client_t* c) {
    if (!c) {
        return;
    }
    std::free(c);
}

extern "C" rac_result_t rac_http_request_send(rac_http_client_t* c, const rac_http_request_t* req,
                                              rac_http_response_t* out_resp) {
    if (!c || !req || !out_resp) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    std::memset(out_resp, 0, sizeof(*out_resp));
    return dispatch_send(req, out_resp);
}

extern "C" rac_result_t rac_http_request_stream(rac_http_client_t* c, const rac_http_request_t* req,
                                                rac_http_body_chunk_fn cb, void* user_data,
                                                rac_http_response_t* out_resp_meta) {
    if (!c || !req || !cb || !out_resp_meta) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    std::memset(out_resp_meta, 0, sizeof(*out_resp_meta));
    return dispatch_stream(req, cb, user_data, out_resp_meta);
}

extern "C" rac_result_t rac_http_request_resume(rac_http_client_t* c, const rac_http_request_t* req,
                                                uint64_t resume_from_byte,
                                                rac_http_body_chunk_fn cb, void* user_data,
                                                rac_http_response_t* out_resp_meta) {
    if (!c || !req || !cb || !out_resp_meta) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    std::memset(out_resp_meta, 0, sizeof(*out_resp_meta));
    return dispatch_resume(req, resume_from_byte, cb, user_data, out_resp_meta);
}

// `rac_http_response_free` lives in
// src/infrastructure/http/rac_http_response.cpp (compiled on every
// target). The default and emscripten clients allocate the response
// fields with std::malloc / strdup so the shared TU can free them
// directly.
