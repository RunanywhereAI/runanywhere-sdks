/**
 * @file rac_http_client_default.cpp
 * @brief Default HTTP client implementation that dispatches every
 *        public C ABI call into the platform transport vtable.
 *
 * Stage S5: libcurl + mbedTLS removed from the build. The public
 * `rac_http_client_*` / `rac_http_request_*` / `rac_http_response_free`
 * symbols are still part of the SDK contract — they are the entry
 * points Kotlin's JNI `httpRequest` bridge, RN's
 * `HybridRunAnywhereCore+Http.cpp`, the Web SDK's `HTTPAdapter.ts`,
 * and `rac_http_download.cpp` all call into. After S5 the only
 * implementation behind these symbols is the platform transport
 * adapter registered via `rac_http_transport_register` (OkHttp on
 * Android, URLSession on Apple, emscripten_fetch / JS fetch on
 * WASM, dart:io on Flutter, etc.).
 *
 * When no adapter is registered the calls fail cleanly with
 * `RAC_ERROR_FEATURE_NOT_AVAILABLE`. Every SDK is responsible for
 * installing an adapter during init (see R1-R5 in the H refactor
 * plan); a silent fallback to libcurl is no longer possible because
 * libcurl is gone.
 *
 * This TU is compiled on every target EXCEPT Emscripten — on WASM
 * `rac_http_client_emscripten.cpp` already provides direct
 * implementations of the same symbols (it's the only HTTP surface in
 * the WASM build), and the linker would see duplicate definitions if
 * both TUs were pulled in.
 */

#include <cstdlib>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/http/rac_http_transport.h"

// =============================================================================
// Internal accessor defined in rac_http_transport.cpp. Returns the
// currently-registered transport ops or false when the router is empty.
// =============================================================================
namespace rac_internal {
bool get_http_transport(const rac_http_transport_ops_t** out_ops, void** out_user_data);
}

namespace {
constexpr const char* kTag = "rac_http_client_default";

// Opaque handle — the transport vtable is stateless at the handle level
// (everything travels through the request struct), so the client exists
// solely to preserve the create/destroy API contract.
struct rac_http_client_impl {
    int _unused;
};
}  // namespace

// =============================================================================
// Lifecycle
// =============================================================================

extern "C" rac_result_t rac_http_client_create(rac_http_client_t** out) {
    if (!out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    auto* handle = static_cast<rac_http_client_impl*>(std::calloc(1, sizeof(rac_http_client_impl)));
    if (!handle) {
        *out = nullptr;
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    *out = reinterpret_cast<rac_http_client_t*>(handle);
    return RAC_SUCCESS;
}

extern "C" void rac_http_client_destroy(rac_http_client_t* c) {
    if (!c) {
        return;
    }
    std::free(c);
}

// =============================================================================
// Dispatch helpers
// =============================================================================

namespace {

rac_result_t dispatch_send(const rac_http_request_t* req, rac_http_response_t* out_resp) {
    const rac_http_transport_ops_t* ops = nullptr;
    void* ud = nullptr;
    if (!rac_internal::get_http_transport(&ops, &ud) || ops == nullptr ||
        ops->request_send == nullptr) {
        RAC_LOG_ERROR(kTag,
                      "rac_http_request_send: no platform HTTP transport registered. "
                      "Every SDK must call rac_http_transport_register() during init.");
        return RAC_ERROR_FEATURE_NOT_AVAILABLE;
    }
    return ops->request_send(ud, req, out_resp);
}

rac_result_t dispatch_stream(const rac_http_request_t* req, rac_http_body_chunk_fn cb,
                             void* user_data, rac_http_response_t* out_resp_meta) {
    const rac_http_transport_ops_t* ops = nullptr;
    void* ud = nullptr;
    if (!rac_internal::get_http_transport(&ops, &ud) || ops == nullptr ||
        ops->request_stream == nullptr) {
        RAC_LOG_ERROR(kTag,
                      "rac_http_request_stream: no platform HTTP transport (or adapter lacks "
                      "request_stream op). Every SDK must register a streaming-capable adapter.");
        return RAC_ERROR_FEATURE_NOT_AVAILABLE;
    }
    return ops->request_stream(ud, req, cb, user_data, out_resp_meta);
}

rac_result_t dispatch_resume(const rac_http_request_t* req, uint64_t resume_from_byte,
                             rac_http_body_chunk_fn cb, void* user_data,
                             rac_http_response_t* out_resp_meta) {
    const rac_http_transport_ops_t* ops = nullptr;
    void* ud = nullptr;
    if (!rac_internal::get_http_transport(&ops, &ud) || ops == nullptr ||
        ops->request_resume == nullptr) {
        RAC_LOG_ERROR(kTag,
                      "rac_http_request_resume: no platform HTTP transport (or adapter lacks "
                      "request_resume op). Every SDK must register a resumable-capable adapter.");
        return RAC_ERROR_FEATURE_NOT_AVAILABLE;
    }
    return ops->request_resume(ud, req, resume_from_byte, cb, user_data, out_resp_meta);
}

}  // namespace

// =============================================================================
// Public C ABI
// =============================================================================

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
