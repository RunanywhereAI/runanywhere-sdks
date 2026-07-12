/**
 * @file http_transport_curl.cpp
 * @brief libcurl-backed rac_http_transport_ops_t for desktop builds.
 *
 * Desktop counterpart of the per-SDK transports (URLSession / OkHttp / fetch /
 * dart:io). One curl easy handle per request — callbacks may fire from any
 * thread, and easy handles are not shareable, so per-call handles keep the
 * implementation lock-free. curl_global_init/cleanup run in the vtable's
 * init/destroy hooks (invoked by rac_http_transport_register).
 *
 * Contract mapping (rac_http_transport.h):
 *   request_send    → buffered body, RAC_SUCCESS on ANY http status
 *   request_stream  → WRITEFUNCTION → chunk cb; cb RAC_FALSE → abort transfer
 *                     (curl reports CURLE_WRITE_ERROR) → RAC_ERROR_CANCELLED
 *   request_resume  → CURLOPT_RESUME_FROM_LARGE (curl emits Range: bytes=N-)
 *   redirects       → always followed (transports auto-follow per contract);
 *                     final URL surfaced via response.redirected_url
 *   allocations     → malloc/rac_strdup so rac_http_response_free() releases
 */

#include <cstdlib>
#include <cstring>
#include <curl/curl.h>
#include <string>
#include <utility>
#include <vector>

#include "rac/core/rac_core.h"
#include "rac/infrastructure/http/rac_http_transport.h"

namespace {

constexpr long kConnectTimeoutMs = 30000;
constexpr long kMaxRedirects = 10;

// -----------------------------------------------------------------------------
// Per-request context
// -----------------------------------------------------------------------------

struct RequestContext {
    // Buffered body (request_send only).
    std::string body;

    // Streaming state (request_stream / request_resume only).
    rac_http_body_chunk_fn chunk_cb = nullptr;
    void* chunk_user_data = nullptr;
    CURL* curl = nullptr;
    uint64_t total_written = 0;
    uint64_t content_length = 0;
    bool content_length_known = false;
    bool cancelled = false;

    // Response headers of the FINAL response (redirect hops clear the list).
    std::vector<std::pair<std::string, std::string>> headers;
};

size_t header_callback(char* buffer, size_t size, size_t nitems, void* user_data) {
    auto* ctx = static_cast<RequestContext*>(user_data);
    const size_t total = size * nitems;
    std::string line(buffer, total);

    // New status line ⇒ new response block (redirect hop): drop prior headers.
    if (line.starts_with("HTTP/")) {
        ctx->headers.clear();
        return total;
    }

    const size_t colon = line.find(':');
    if (colon != std::string::npos) {
        std::string name = line.substr(0, colon);
        std::string value = line.substr(colon + 1);
        const auto trim = [](std::string& s) {
            while (!s.empty() &&
                   (s.back() == '\r' || s.back() == '\n' || s.back() == ' ' || s.back() == '\t')) {
                s.pop_back();
            }
            size_t start = 0;
            while (start < s.size() && (s[start] == ' ' || s[start] == '\t')) {
                ++start;
            }
            s.erase(0, start);
        };
        trim(name);
        trim(value);
        if (!name.empty()) {
            ctx->headers.emplace_back(std::move(name), std::move(value));
        }
    }
    return total;
}

size_t buffer_write_callback(char* data, size_t size, size_t nmemb, void* user_data) {
    auto* ctx = static_cast<RequestContext*>(user_data);
    const size_t total = size * nmemb;
    ctx->body.append(data, total);
    return total;
}

size_t stream_write_callback(char* data, size_t size, size_t nmemb, void* user_data) {
    auto* ctx = static_cast<RequestContext*>(user_data);
    const size_t total = size * nmemb;

    if (!ctx->content_length_known) {
        curl_off_t declared = -1;
        if (curl_easy_getinfo(ctx->curl, CURLINFO_CONTENT_LENGTH_DOWNLOAD_T, &declared) ==
                CURLE_OK &&
            declared > 0) {
            ctx->content_length = static_cast<uint64_t>(declared);
        }
        ctx->content_length_known = true;
    }

    ctx->total_written += total;
    const rac_bool_t keep_going =
        ctx->chunk_cb(reinterpret_cast<const uint8_t*>(data), total, ctx->total_written,
                      ctx->content_length, ctx->chunk_user_data);
    if (keep_going == RAC_FALSE) {
        ctx->cancelled = true;
        return 0;  // short write aborts the transfer (CURLE_WRITE_ERROR)
    }
    return total;
}

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

rac_result_t map_curl_code(CURLcode code, const RequestContext& ctx) {
    switch (code) {
        case CURLE_OK:
            return RAC_SUCCESS;
        case CURLE_OPERATION_TIMEDOUT:
            return RAC_ERROR_TIMEOUT;
        case CURLE_WRITE_ERROR:
        case CURLE_ABORTED_BY_CALLBACK:
            return ctx.cancelled ? RAC_ERROR_CANCELLED : RAC_ERROR_NETWORK_ERROR;
        case CURLE_OUT_OF_MEMORY:
            return RAC_ERROR_OUT_OF_MEMORY;
        case CURLE_URL_MALFORMAT:
        case CURLE_UNSUPPORTED_PROTOCOL:
            return RAC_ERROR_INVALID_ARGUMENT;
        default:
            return RAC_ERROR_NETWORK_ERROR;
    }
}

struct EasyHandle {
    CURL* curl = curl_easy_init();
    curl_slist* header_list = nullptr;

    ~EasyHandle() {
        if (header_list) {
            curl_slist_free_all(header_list);
        }
        if (curl) {
            curl_easy_cleanup(curl);
        }
    }
};

// Configures everything shared by buffered + streaming requests. Returns
// RAC_SUCCESS or an argument-validation error.
rac_result_t configure_request(EasyHandle& handle, const rac_http_request_t* req,
                               RequestContext& ctx) {
    if (!handle.curl) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    if (!req || !req->url || !req->method) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    CURL* curl = handle.curl;
    curl_easy_setopt(curl, CURLOPT_URL, req->url);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, req->follow_redirects != RAC_FALSE ? 1L : 0L);
    curl_easy_setopt(curl, CURLOPT_MAXREDIRS, kMaxRedirects);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS, kConnectTimeoutMs);
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);  // required for multi-threaded use
    curl_easy_setopt(curl, CURLOPT_ACCEPT_ENCODING, "");

    static const std::string user_agent =
        std::string("RunAnywhereSDK/") + rac_get_version().string + " (desktop)";
    curl_easy_setopt(curl, CURLOPT_USERAGENT, user_agent.c_str());

    if (req->timeout_ms > 0) {
        curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, static_cast<long>(req->timeout_ms));
    }

    const bool is_get = std::strcmp(req->method, "GET") == 0;
    const bool is_head = std::strcmp(req->method, "HEAD") == 0;
    if (is_get) {
        curl_easy_setopt(curl, CURLOPT_HTTPGET, 1L);
    } else if (is_head) {
        curl_easy_setopt(curl, CURLOPT_NOBODY, 1L);
    } else {
        curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, req->method);
        if (req->body_bytes && req->body_len > 0) {
            curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE_LARGE,
                             static_cast<curl_off_t>(req->body_len));
            curl_easy_setopt(curl, CURLOPT_COPYPOSTFIELDS,
                             reinterpret_cast<const char*>(req->body_bytes));
        }
    }

    for (size_t i = 0; i < req->header_count; ++i) {
        const rac_http_header_kv_t& kv = req->headers[i];
        if (!kv.name || !kv.value) {
            continue;
        }
        const std::string line = std::string(kv.name) + ": " + kv.value;
        handle.header_list = curl_slist_append(handle.header_list, line.c_str());
    }
    if (handle.header_list) {
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, handle.header_list);
    }

    curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, header_callback);
    curl_easy_setopt(curl, CURLOPT_HEADERDATA, &ctx);
    return RAC_SUCCESS;
}

// Fills status / headers / redirected_url / elapsed_ms from a completed
// transfer. Header + url strings are malloc-allocated for rac_http_response_free.
void populate_response_meta(CURL* curl, const rac_http_request_t* req, const RequestContext& ctx,
                            rac_http_response_t* out_resp) {
    long status = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status);
    out_resp->status = static_cast<int32_t>(status);

    if (!ctx.headers.empty()) {
        auto* kvs = static_cast<rac_http_header_kv_t*>(
            std::calloc(ctx.headers.size(), sizeof(rac_http_header_kv_t)));
        if (kvs) {
            for (size_t i = 0; i < ctx.headers.size(); ++i) {
                kvs[i].name = rac_strdup(ctx.headers[i].first.c_str());
                kvs[i].value = rac_strdup(ctx.headers[i].second.c_str());
            }
            out_resp->headers = kvs;
            out_resp->header_count = ctx.headers.size();
        }
    }

    char* effective_url = nullptr;
    if (curl_easy_getinfo(curl, CURLINFO_EFFECTIVE_URL, &effective_url) == CURLE_OK &&
        effective_url && req->url && std::strcmp(effective_url, req->url) != 0) {
        out_resp->redirected_url = rac_strdup(effective_url);
    }

    curl_off_t elapsed_us = 0;
    if (curl_easy_getinfo(curl, CURLINFO_TOTAL_TIME_T, &elapsed_us) == CURLE_OK) {
        out_resp->elapsed_ms = static_cast<uint64_t>(elapsed_us / 1000);
    }
}

// -----------------------------------------------------------------------------
// Vtable implementation
// -----------------------------------------------------------------------------

rac_result_t curl_request_send(void* /*user_data*/, const rac_http_request_t* req,
                               rac_http_response_t* out_resp) {
    if (!out_resp) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    std::memset(out_resp, 0, sizeof(*out_resp));

    EasyHandle handle;
    RequestContext ctx;
    rac_result_t rc = configure_request(handle, req, ctx);
    if (rc != RAC_SUCCESS) {
        return rc;
    }

    curl_easy_setopt(handle.curl, CURLOPT_WRITEFUNCTION, buffer_write_callback);
    curl_easy_setopt(handle.curl, CURLOPT_WRITEDATA, &ctx);

    const CURLcode code = curl_easy_perform(handle.curl);
    if (code != CURLE_OK) {
        return map_curl_code(code, ctx);
    }

    populate_response_meta(handle.curl, req, ctx, out_resp);

    if (!ctx.body.empty()) {
        auto* body = static_cast<uint8_t*>(std::malloc(ctx.body.size()));
        if (!body) {
            rac_http_response_free(out_resp);
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        std::memcpy(body, ctx.body.data(), ctx.body.size());
        out_resp->body_bytes = body;
        out_resp->body_len = ctx.body.size();
    }
    return RAC_SUCCESS;
}

rac_result_t run_streaming(const rac_http_request_t* req, uint64_t resume_from_byte,
                           rac_http_body_chunk_fn cb, void* cb_user_data,
                           rac_http_response_t* out_resp_meta) {
    if (!out_resp_meta || !cb) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    std::memset(out_resp_meta, 0, sizeof(*out_resp_meta));

    EasyHandle handle;
    RequestContext ctx;
    rac_result_t rc = configure_request(handle, req, ctx);
    if (rc != RAC_SUCCESS) {
        return rc;
    }

    ctx.chunk_cb = cb;
    ctx.chunk_user_data = cb_user_data;
    ctx.curl = handle.curl;
    if (resume_from_byte > 0) {
        curl_easy_setopt(handle.curl, CURLOPT_RESUME_FROM_LARGE,
                         static_cast<curl_off_t>(resume_from_byte));
        // total_written counts bytes delivered THIS transfer; the orchestrator
        // owns on-disk offsets for resumed downloads.
    }

    curl_easy_setopt(handle.curl, CURLOPT_WRITEFUNCTION, stream_write_callback);
    curl_easy_setopt(handle.curl, CURLOPT_WRITEDATA, &ctx);

    const CURLcode code = curl_easy_perform(handle.curl);
    if (code != CURLE_OK) {
        return map_curl_code(code, ctx);
    }

    populate_response_meta(handle.curl, req, ctx, out_resp_meta);
    return RAC_SUCCESS;
}

rac_result_t curl_request_stream(void* /*user_data*/, const rac_http_request_t* req,
                                 rac_http_body_chunk_fn cb, void* cb_user_data,
                                 rac_http_response_t* out_resp_meta) {
    return run_streaming(req, 0, cb, cb_user_data, out_resp_meta);
}

rac_result_t curl_request_resume(void* /*user_data*/, const rac_http_request_t* req,
                                 uint64_t resume_from_byte, rac_http_body_chunk_fn cb,
                                 void* cb_user_data, rac_http_response_t* out_resp_meta) {
    return run_streaming(req, resume_from_byte, cb, cb_user_data, out_resp_meta);
}

rac_result_t curl_transport_init(void* /*user_data*/) {
    return curl_global_init(CURL_GLOBAL_DEFAULT) == CURLE_OK ? RAC_SUCCESS
                                                             : RAC_ERROR_NETWORK_ERROR;
}

void curl_transport_destroy(void* /*user_data*/) {
    curl_global_cleanup();
}

// Static lifetime: rac_http_transport_register keeps the pointer.
const rac_http_transport_ops_t kCurlTransportOps = {
    curl_request_send,   curl_request_stream,    curl_request_resume,
    curl_transport_init, curl_transport_destroy,
};

}  // namespace

extern "C" rac_result_t rac_desktop_http_transport_register(void) {
    return rac_http_transport_register(&kCurlTransportOps, nullptr);
}
