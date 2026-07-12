/**
 * @file rac_http_client_default.cpp
 * @brief Default HTTP client implementation that dispatches every
 *        public C ABI call into the platform transport vtable.
 *
 * libcurl + mbedTLS removed from the build. The public
 * `rac_http_client_*` / `rac_http_request_*` / `rac_http_response_free`
 * symbols are still part of the SDK contract — they are the entry
 * points Kotlin's JNI `httpRequest` bridge, RN's
 * `HybridRunAnywhereCore+Http.cpp`, the Web SDK's `HTTPAdapter.ts`,
 * and `rac_http_download.cpp` all call into. The only
 * implementation behind these symbols is the platform transport
 * adapter registered via `rac_http_transport_register` (OkHttp on
 * Android, URLSession on Apple, emscripten_fetch / JS fetch on
 * WASM, dart:io on Flutter, etc.).
 *
 * When no adapter is registered the calls fail cleanly with
 * `RAC_ERROR_FEATURE_NOT_AVAILABLE`. Every SDK is responsible for
 * installing an adapter during init; a silent fallback to libcurl
 * is no longer possible because libcurl is gone.
 *
 * This TU is compiled on every target EXCEPT Emscripten — on WASM
 * `rac_http_client_emscripten.cpp` already provides direct
 * implementations of the same symbols (it's the only HTTP surface in
 * the WASM build), and the linker would see duplicate definitions if
 * both TUs were pulled in.
 */

#include "rac_http_hf_auth.h"
#include "rac_http_transport_ref.h"
#include "rac_http_upsert_mode.h"

#include <cstdlib>
#include <cstring>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/http/rac_http_transport.h"

// Maps POSIX strcasecmp -> _stricmp on Windows (MSVC). Without it the
// strcasecmp() call below fails to compile on Windows (error C3861). No-op on
// non-Windows platforms.
#include "core/internal/platform_compat.h"

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

/// Result of merging an upsert transform into a request descriptor.
/// `effective_request` is the descriptor to hand to the adapter — it
/// either references `req` directly (when no transform was armed) or a
/// stack-built copy with rewritten URL + augmented headers.
///
/// `header_storage` and the `effective_request.headers` array members
/// must out-live the dispatch call; both live in this struct.
struct PreparedRequest {
    rac_http_request_t effective_request{};
    std::vector<rac_http_header_kv_t> header_storage;  // valid only when transformed
    std::string url_storage;                           // backing for transformed url
    std::string prefer_value_storage;                  // backing for "Prefer" header
    std::string auth_value_storage;                    // backing for "Authorization" header
    bool transformed = false;
};

bool has_authorization_header(const rac_http_request_t* req) {
    for (size_t i = 0; i < req->header_count; ++i) {
        const char* name = req->headers[i].name;
        if (name != nullptr && strcasecmp(name, "Authorization") == 0) {
            return true;
        }
    }
    return false;
}

/// Builds the descriptor passed to the platform transport. When upsert
/// mode is engaged we rewrite the URL and append a `Prefer` header; when a
/// Hugging Face token is configured and the URL is an HF host we append the
/// bearer Authorization header; otherwise we pass `*req` through unchanged.
PreparedRequest prepare_request(const rac_http_request_t* req) {
    PreparedRequest prepared;
    auto transform = rac::http::consume_upsert_transform(req);
    std::string hf_bearer = rac::http::hf_bearer_for_url(req->url, has_authorization_header(req));
    if (!transform.engaged && hf_bearer.empty()) {
        prepared.effective_request = *req;
        return prepared;
    }

    prepared.transformed = true;
    prepared.effective_request = *req;

    // Copy existing headers, then append the armed extras.
    prepared.header_storage.reserve(req->header_count + 2);
    for (size_t i = 0; i < req->header_count; ++i) {
        prepared.header_storage.push_back(req->headers[i]);
    }
    if (transform.engaged) {
        prepared.url_storage = std::move(transform.transformed_url);
        prepared.prefer_value_storage = std::move(transform.prefer_header_value);
        prepared.header_storage.push_back(
            rac_http_header_kv_t{"Prefer", prepared.prefer_value_storage.c_str()});
        prepared.effective_request.url = prepared.url_storage.c_str();
    }
    if (!hf_bearer.empty()) {
        prepared.auth_value_storage = std::move(hf_bearer);
        prepared.header_storage.push_back(
            rac_http_header_kv_t{"Authorization", prepared.auth_value_storage.c_str()});
    }

    prepared.effective_request.headers = prepared.header_storage.data();
    prepared.effective_request.header_count = prepared.header_storage.size();
    return prepared;
}

rac_result_t dispatch_send(const rac_http_request_t* req, rac_http_response_t* out_resp) {
    rac_internal::TransportRef transport;
    if (!transport || transport.ops()->request_send == nullptr) {
        RAC_LOG_ERROR(kTag,
                      "rac_http_request_send: no platform HTTP transport registered. "
                      "Every SDK must call rac_http_transport_register() during init.");
        return RAC_ERROR_FEATURE_NOT_AVAILABLE;
    }
    PreparedRequest prepared = prepare_request(req);
    return transport.ops()->request_send(transport.user_data(), &prepared.effective_request,
                                         out_resp);
}

rac_result_t dispatch_stream(const rac_http_request_t* req, rac_http_body_chunk_fn cb,
                             void* user_data, rac_http_response_t* out_resp_meta) {
    rac_internal::TransportRef transport;
    if (!transport || transport.ops()->request_stream == nullptr) {
        RAC_LOG_ERROR(kTag,
                      "rac_http_request_stream: no platform HTTP transport (or adapter lacks "
                      "request_stream op). Every SDK must register a streaming-capable adapter.");
        return RAC_ERROR_FEATURE_NOT_AVAILABLE;
    }
    PreparedRequest prepared = prepare_request(req);
    return transport.ops()->request_stream(transport.user_data(), &prepared.effective_request, cb,
                                           user_data, out_resp_meta);
}

rac_result_t dispatch_resume(const rac_http_request_t* req, uint64_t resume_from_byte,
                             rac_http_body_chunk_fn cb, void* user_data,
                             rac_http_response_t* out_resp_meta) {
    rac_internal::TransportRef transport;
    if (!transport || transport.ops()->request_resume == nullptr) {
        RAC_LOG_ERROR(kTag,
                      "rac_http_request_resume: no platform HTTP transport (or adapter lacks "
                      "request_resume op). Every SDK must register a resumable-capable adapter.");
        return RAC_ERROR_FEATURE_NOT_AVAILABLE;
    }
    PreparedRequest prepared = prepare_request(req);
    return transport.ops()->request_resume(transport.user_data(), &prepared.effective_request,
                                           resume_from_byte, cb, user_data, out_resp_meta);
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

// `rac_http_response_free` lives in
// src/infrastructure/http/rac_http_response.cpp (compiled on every
// target). The default and emscripten clients allocate the response
// fields with std::malloc / strdup so the shared TU can free them
// directly.
