/**
 * @file rac_http_client_emscripten.cpp
 * @brief Emscripten Fetch-backed HTTP transport adapter.
 *
 * v2 close-out Phase H7 refactor — instead of replacing the libcurl
 * client wholesale (B03 did this as a "WASM is special" fork) this
 * file now registers itself through the platform HTTP transport vtable
 * declared in `include/rac/infrastructure/http/rac_http_transport.h`.
 *
 * The libcurl-backed `rac_http_request_*` entry points in
 * `rac_http_client_curl.cpp` consult the transport registry first and
 * short-circuit to us when we're installed. Doing it that way means
 * the WASM build goes through the same one-pattern routing used by
 * the Swift URLSession / Kotlin OkHttp / Flutter dart:io / RN fetch
 * adapters instead of compiling a second, parallel C ABI shim.
 *
 * The actual emscripten_fetch() logic below is unchanged from B03 —
 * only the wiring is different. See `rac_http_transport.h` for the
 * ownership / threading contract every adapter must satisfy:
 *   - callbacks can be invoked from any thread (we block on
 *     EMSCRIPTEN_FETCH_SYNCHRONOUS so "any thread" means the worker
 *     pthread that issued the request),
 *   - strings/bytes handed to us are caller-owned,
 *   - out_resp fields must be heap-allocated with the same
 *     malloc/strdup contract as the libcurl default (so the shared
 *     `rac_http_response_free` frees them correctly).
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
 * Limitations vs. the libcurl backend:
 *   - No cookie jar (the browser's own cookies are used per CORS
 *     rules; the SDK never sees them).
 *   - No CURLOPT_FOLLOWLOCATION toggle: `fetch()` always follows
 *     redirects per `redirect: "follow"` (the default).
 *   - `total_time` is derived from a wall-clock measurement around the
 *     blocking `emscripten_fetch` call.
 *   - Streaming body callbacks are fired once with the whole buffer
 *     (the Fetch API's `ReadableStream` requires async JS glue that's
 *     out of scope for the MVP). Download byte counts remain correct;
 *     only the progress granularity is coarser than libcurl.
 *   - Response headers are parsed from
 *     `emscripten_fetch_get_response_headers_length` /
 *     `..._get_response_headers`.
 */

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

    // Effective URL after redirects — not natively reported, fall back to the request URL.
    out->redirected_url = strdup(req->url);

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
// Transport vtable ops (v2 close-out Phase H7)
//
// These are the thin shims the transport router in
// `rac_http_transport.cpp` calls into after short-circuiting around
// libcurl. Signature matches `rac_http_transport_ops_t` — the leading
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
    /*.request_send   =*/ emscripten_request_send,
    /*.request_stream =*/ emscripten_request_stream,
    /*.request_resume =*/ emscripten_request_resume,
    /*.init           =*/ nullptr,
    /*.destroy        =*/ nullptr,
};

}  // namespace

// =============================================================================
// Public registration API — JS calls this once after the WASM module
// loads so the libcurl router in `rac_http_client_curl.cpp` starts
// short-circuiting here for every HTTP request. (Note: on WASM the
// libcurl `.cpp` itself isn't compiled in — the router lookup lives
// in `rac_http_transport.cpp` which IS compiled unconditionally, and
// the `rac_http_request_*` symbols we used to export directly from
// this file are now provided by whichever TU wires the transport in.
// Since this is still the only HTTP implementation in the WASM build,
// we continue to export those symbols as well for back-compat with
// anything that linked against the B03 shim.)
// =============================================================================

extern "C" RAC_API rac_result_t rac_http_transport_register_emscripten(void) {
    RAC_LOG_INFO(kTag, "Registering emscripten_fetch HTTP transport");
    return rac_http_transport_register(&kEmscriptenOps, /*user_data=*/nullptr);
}

// =============================================================================
// Opaque handle — keep the shape identical to the curl backend so
// downstream code (`rac_http_download.cpp`) treats both the same.
// =============================================================================

struct rac_http_client {
    // Emscripten Fetch is stateless at the handle level; the struct
    // exists solely so the API contract (create/destroy pair) holds.
    int _unused;
};

// =============================================================================
// Public API (back-compat with B03).
//
// On WASM builds libcurl is skipped entirely (see CMakeLists.txt), so
// these symbols MUST still be provided by this TU for linkers that
// resolve the `rac_http_request_*` family against it directly. When
// the JS side has called `rac_http_transport_register_emscripten()`,
// the transport registry is populated but the lookup only fires from
// `rac_http_client_curl.cpp` — which isn't compiled on WASM. Keeping
// direct implementations here preserves B03's behaviour for existing
// callers while the new vtable-registration symbol is additive.
// =============================================================================

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
    return emscripten_request_send(/*user_data=*/nullptr, req, out_resp);
}

extern "C" rac_result_t rac_http_request_stream(rac_http_client_t* c, const rac_http_request_t* req,
                                                rac_http_body_chunk_fn cb, void* user_data,
                                                rac_http_response_t* out_resp_meta) {
    if (!c || !req || !cb || !out_resp_meta) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    return emscripten_request_stream(/*user_data=*/nullptr, req, cb, user_data, out_resp_meta);
}

extern "C" rac_result_t rac_http_request_resume(rac_http_client_t* c, const rac_http_request_t* req,
                                                uint64_t resume_from_byte,
                                                rac_http_body_chunk_fn cb, void* user_data,
                                                rac_http_response_t* out_resp_meta) {
    if (!c || !req || !cb || !out_resp_meta) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    return emscripten_request_resume(/*user_data=*/nullptr, req, resume_from_byte, cb, user_data,
                                     out_resp_meta);
}

extern "C" void rac_http_response_free(rac_http_response_t* resp) {
    if (!resp) {
        return;
    }
    if (resp->body_bytes) {
        std::free(resp->body_bytes);
        resp->body_bytes = nullptr;
    }
    resp->body_len = 0;
    if (resp->headers) {
        for (size_t i = 0; i < resp->header_count; ++i) {
            if (resp->headers[i].name) {
                std::free(const_cast<char*>(resp->headers[i].name));
            }
            if (resp->headers[i].value) {
                std::free(const_cast<char*>(resp->headers[i].value));
            }
        }
        std::free(resp->headers);
        resp->headers = nullptr;
    }
    resp->header_count = 0;
    if (resp->redirected_url) {
        std::free(resp->redirected_url);
        resp->redirected_url = nullptr;
    }
    resp->status = 0;
    resp->elapsed_ms = 0;
}
