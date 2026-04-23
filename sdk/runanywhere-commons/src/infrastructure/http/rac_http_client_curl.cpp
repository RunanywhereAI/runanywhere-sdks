/**
 * @file rac_http_client_curl.cpp
 * @brief libcurl-backed implementation of the `rac_http_client_*` C ABI.
 *
 * See `include/rac/infrastructure/http/rac_http_client.h` for the
 * contract. See `docs/rfcs/h1_http_client_vendor.md` for why libcurl.
 *
 * Threading: one libcurl easy handle per `rac_http_client_t`. The
 * handle is NOT shared across threads — callers allocate one per
 * worker. No global state is kept inside the implementation except
 * for the process-wide `curl_global_init` / `curl_global_cleanup`
 * refcount, which is ref-counted off the live-instance tally.
 */

#include "rac/infrastructure/http/rac_http_client.h"

#include <curl/curl.h>

#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <new>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"

namespace {

constexpr const char* kTag = "rac_http_client";

// =============================================================================
// Process-wide libcurl init/cleanup is ref-counted off live instances.
// =============================================================================

std::mutex& g_global_mutex() {
    static std::mutex m;
    return m;
}

size_t& g_global_refcount() {
    static size_t n = 0;
    return n;
}

rac_result_t global_init_once() {
    std::lock_guard<std::mutex> lk(g_global_mutex());
    if (g_global_refcount() == 0) {
        CURLcode rc = curl_global_init(CURL_GLOBAL_DEFAULT);
        if (rc != CURLE_OK) {
            RAC_LOG_ERROR(kTag, "curl_global_init failed: %d", static_cast<int>(rc));
            return RAC_ERROR_INTERNAL;
        }
    }
    ++g_global_refcount();
    return RAC_SUCCESS;
}

void global_cleanup_once() {
    std::lock_guard<std::mutex> lk(g_global_mutex());
    if (g_global_refcount() == 0) {
        return;
    }
    if (--g_global_refcount() == 0) {
        curl_global_cleanup();
    }
}

// =============================================================================
// Per-transfer contexts passed through libcurl's void* user_data slots.
// =============================================================================

struct buffer_write_ctx {
    std::vector<uint8_t> body;
};

struct stream_write_ctx {
    rac_http_body_chunk_fn cb;
    void* user_data;
    uint64_t total_written;
    uint64_t content_length;
    bool cancelled;
};

struct header_capture_ctx {
    std::vector<std::pair<std::string, std::string>> headers;
};

// =============================================================================
// Callbacks invoked by libcurl.
// =============================================================================

size_t write_to_buffer(char* ptr, size_t size, size_t nmemb, void* user) {
    const size_t len = size * nmemb;
    auto* ctx = static_cast<buffer_write_ctx*>(user);
    ctx->body.insert(ctx->body.end(), reinterpret_cast<uint8_t*>(ptr),
                     reinterpret_cast<uint8_t*>(ptr) + len);
    return len;
}

size_t write_to_stream(char* ptr, size_t size, size_t nmemb, void* user) {
    const size_t len = size * nmemb;
    auto* ctx = static_cast<stream_write_ctx*>(user);

    // Invoke the user callback — returning RAC_FALSE cancels.
    ctx->total_written += len;
    rac_bool_t keep_going = ctx->cb(reinterpret_cast<const uint8_t*>(ptr), len, ctx->total_written,
                                    ctx->content_length, ctx->user_data);
    if (keep_going == RAC_FALSE) {
        ctx->cancelled = true;
        // Returning anything != len aborts the transfer (libcurl convention).
        return 0;
    }
    return len;
}

size_t capture_header(char* ptr, size_t size, size_t nitems, void* user) {
    const size_t len = size * nitems;
    auto* ctx = static_cast<header_capture_ctx*>(user);

    // Parse "Name: Value\r\n" — skip status lines and empty terminators.
    std::string line(ptr, len);
    // Strip trailing CRLF.
    while (!line.empty() && (line.back() == '\n' || line.back() == '\r')) {
        line.pop_back();
    }
    if (line.empty()) {
        return len;
    }
    // Skip the HTTP status line ("HTTP/1.1 200 OK").
    if (line.rfind("HTTP/", 0) == 0) {
        // A new response is starting (e.g. after a redirect hop); reset
        // any headers captured so far so we end up with the headers of
        // the final response.
        ctx->headers.clear();
        return len;
    }
    const auto colon = line.find(':');
    if (colon == std::string::npos) {
        return len;
    }
    std::string name = line.substr(0, colon);
    std::string value = line.substr(colon + 1);
    // Trim leading whitespace on value.
    size_t i = 0;
    while (i < value.size() && (value[i] == ' ' || value[i] == '\t')) {
        ++i;
    }
    value.erase(0, i);
    ctx->headers.emplace_back(std::move(name), std::move(value));
    return len;
}

// =============================================================================
// Method / header helpers.
// =============================================================================

bool method_is_get(const char* m) {
    return m != nullptr && std::strcmp(m, "GET") == 0;
}
bool method_is_head(const char* m) { return m != nullptr && std::strcmp(m, "HEAD") == 0; }
bool method_has_body(const char* m) {
    return m != nullptr && (std::strcmp(m, "POST") == 0 || std::strcmp(m, "PUT") == 0 ||
                            std::strcmp(m, "PATCH") == 0 || std::strcmp(m, "DELETE") == 0);
}

struct curl_slist_owner {
    struct curl_slist* list = nullptr;
    ~curl_slist_owner() {
        if (list) {
            curl_slist_free_all(list);
        }
    }
    curl_slist_owner() = default;
    curl_slist_owner(const curl_slist_owner&) = delete;
    curl_slist_owner& operator=(const curl_slist_owner&) = delete;
};

rac_result_t build_header_slist(const rac_http_request_t* req, curl_slist_owner* owner) {
    for (size_t i = 0; i < req->header_count; ++i) {
        const auto& h = req->headers[i];
        if (!h.name || !h.value) {
            return RAC_ERROR_INVALID_ARGUMENT;
        }
        std::string combined = std::string(h.name) + ": " + h.value;
        struct curl_slist* next = curl_slist_append(owner->list, combined.c_str());
        if (!next) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        owner->list = next;
    }
    return RAC_SUCCESS;
}

rac_result_t curlcode_to_rac(CURLcode rc) {
    switch (rc) {
        case CURLE_OK:
            return RAC_SUCCESS;
        case CURLE_UNSUPPORTED_PROTOCOL:
        case CURLE_URL_MALFORMAT:
            return RAC_ERROR_INVALID_ARGUMENT;
        case CURLE_COULDNT_RESOLVE_PROXY:
        case CURLE_COULDNT_RESOLVE_HOST:
        case CURLE_COULDNT_CONNECT:
        case CURLE_SSL_CONNECT_ERROR:
        case CURLE_PEER_FAILED_VERIFICATION:
        case CURLE_SSL_CERTPROBLEM:
        case CURLE_SSL_CACERT_BADFILE:
        case CURLE_RECV_ERROR:
        case CURLE_SEND_ERROR:
            return RAC_ERROR_NETWORK_ERROR;
        case CURLE_OPERATION_TIMEDOUT:
            return RAC_ERROR_TIMEOUT;
        case CURLE_ABORTED_BY_CALLBACK:
        case CURLE_WRITE_ERROR:
            return RAC_ERROR_CANCELLED;
        case CURLE_OUT_OF_MEMORY:
            return RAC_ERROR_OUT_OF_MEMORY;
        default:
            return RAC_ERROR_INTERNAL;
    }
}

// =============================================================================
// Populate the `out_resp` struct from captured state. Ownership is
// transferred to the response struct — caller must invoke
// rac_http_response_free(resp) exactly once.
// =============================================================================

void fill_response_meta(CURL* curl, header_capture_ctx* hdrs, rac_http_response_t* out) {
    long status = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status);
    out->status = static_cast<int32_t>(status);

    double total_time = 0.0;
    curl_easy_getinfo(curl, CURLINFO_TOTAL_TIME, &total_time);
    out->elapsed_ms = static_cast<uint64_t>(total_time * 1000.0);

    char* effective = nullptr;
    curl_easy_getinfo(curl, CURLINFO_EFFECTIVE_URL, &effective);
    out->redirected_url = (effective ? strdup(effective) : nullptr);

    out->header_count = hdrs->headers.size();
    out->headers = nullptr;
    if (!hdrs->headers.empty()) {
        out->headers = static_cast<rac_http_header_kv_t*>(
            std::calloc(hdrs->headers.size(), sizeof(rac_http_header_kv_t)));
        if (!out->headers) {
            out->header_count = 0;
            return;
        }
        for (size_t i = 0; i < hdrs->headers.size(); ++i) {
            out->headers[i].name = strdup(hdrs->headers[i].first.c_str());
            out->headers[i].value = strdup(hdrs->headers[i].second.c_str());
        }
    }
}

// =============================================================================
// Shared request setup.
// =============================================================================

rac_result_t validate_and_setup(CURL* curl, const rac_http_request_t* req,
                                curl_slist_owner* headers_owner) {
    if (!req || !req->url || !req->method) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    curl_easy_reset(curl);
    curl_easy_setopt(curl, CURLOPT_URL, req->url);
    curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 1L);
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);  // multi-thread safe
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "RunAnywhere-SDK-Commons/1.0");

    // Timeouts.
    if (req->timeout_ms > 0) {
        curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, static_cast<long>(req->timeout_ms));
    }

    // Redirects.
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION,
                     req->follow_redirects == RAC_TRUE ? 1L : 0L);
    curl_easy_setopt(curl, CURLOPT_MAXREDIRS, 10L);

    // TLS defaults — use the platform's native certificate store.
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 2L);

    // Method.
    if (method_is_get(req->method)) {
        curl_easy_setopt(curl, CURLOPT_HTTPGET, 1L);
    } else if (method_is_head(req->method)) {
        curl_easy_setopt(curl, CURLOPT_NOBODY, 1L);
    } else {
        curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, req->method);
        if (method_has_body(req->method) && req->body_bytes && req->body_len > 0) {
            curl_easy_setopt(curl, CURLOPT_POSTFIELDS, req->body_bytes);
            curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE_LARGE,
                             static_cast<curl_off_t>(req->body_len));
        } else if (method_has_body(req->method)) {
            // Body-bearing method with no body — still send Content-Length: 0.
            curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE_LARGE, static_cast<curl_off_t>(0));
            curl_easy_setopt(curl, CURLOPT_POSTFIELDS, "");
        }
    }

    // Custom headers.
    rac_result_t hrc = build_header_slist(req, headers_owner);
    if (hrc != RAC_SUCCESS) {
        return hrc;
    }
    if (headers_owner->list) {
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers_owner->list);
    }

    return RAC_SUCCESS;
}

}  // namespace

// =============================================================================
// Opaque handle.
// =============================================================================

struct rac_http_client {
    CURL* curl = nullptr;
};

// =============================================================================
// Public API.
// =============================================================================

extern "C" rac_result_t rac_http_client_create(rac_http_client_t** out) {
    if (!out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *out = nullptr;

    rac_result_t gr = global_init_once();
    if (gr != RAC_SUCCESS) {
        return gr;
    }

    auto* c = new (std::nothrow) rac_http_client();
    if (!c) {
        global_cleanup_once();
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    c->curl = curl_easy_init();
    if (!c->curl) {
        delete c;
        global_cleanup_once();
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    *out = c;
    return RAC_SUCCESS;
}

extern "C" void rac_http_client_destroy(rac_http_client_t* c) {
    if (!c) {
        return;
    }
    if (c->curl) {
        curl_easy_cleanup(c->curl);
    }
    delete c;
    global_cleanup_once();
}

extern "C" rac_result_t rac_http_request_send(rac_http_client_t* c, const rac_http_request_t* req,
                                              rac_http_response_t* out_resp) {
    if (!c || !c->curl || !req || !out_resp) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    std::memset(out_resp, 0, sizeof(*out_resp));

    curl_slist_owner hdrs_owner;
    rac_result_t setup = validate_and_setup(c->curl, req, &hdrs_owner);
    if (setup != RAC_SUCCESS) {
        return setup;
    }

    buffer_write_ctx body_ctx;
    header_capture_ctx hdr_ctx;
    curl_easy_setopt(c->curl, CURLOPT_WRITEFUNCTION, write_to_buffer);
    curl_easy_setopt(c->curl, CURLOPT_WRITEDATA, &body_ctx);
    curl_easy_setopt(c->curl, CURLOPT_HEADERFUNCTION, capture_header);
    curl_easy_setopt(c->curl, CURLOPT_HEADERDATA, &hdr_ctx);

    CURLcode rc = curl_easy_perform(c->curl);
    fill_response_meta(c->curl, &hdr_ctx, out_resp);

    if (rc != CURLE_OK) {
        // Populate the body anyway (partial) — some callers log it.
        out_resp->body_bytes = nullptr;
        out_resp->body_len = 0;
        return curlcode_to_rac(rc);
    }

    if (!body_ctx.body.empty()) {
        out_resp->body_len = body_ctx.body.size();
        out_resp->body_bytes = static_cast<uint8_t*>(std::malloc(body_ctx.body.size()));
        if (!out_resp->body_bytes) {
            out_resp->body_len = 0;
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        std::memcpy(out_resp->body_bytes, body_ctx.body.data(), body_ctx.body.size());
    }
    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_http_request_stream(rac_http_client_t* c,
                                                const rac_http_request_t* req,
                                                rac_http_body_chunk_fn cb, void* user_data,
                                                rac_http_response_t* out_resp_meta) {
    if (!c || !c->curl || !req || !cb || !out_resp_meta) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    std::memset(out_resp_meta, 0, sizeof(*out_resp_meta));

    curl_slist_owner hdrs_owner;
    rac_result_t setup = validate_and_setup(c->curl, req, &hdrs_owner);
    if (setup != RAC_SUCCESS) {
        return setup;
    }

    stream_write_ctx stream_ctx{cb, user_data, 0, 0, false};
    header_capture_ctx hdr_ctx;
    curl_easy_setopt(c->curl, CURLOPT_WRITEFUNCTION, write_to_stream);
    curl_easy_setopt(c->curl, CURLOPT_WRITEDATA, &stream_ctx);
    curl_easy_setopt(c->curl, CURLOPT_HEADERFUNCTION, capture_header);
    curl_easy_setopt(c->curl, CURLOPT_HEADERDATA, &hdr_ctx);

    CURLcode rc = curl_easy_perform(c->curl);

    // After perform we can query Content-Length — re-seed the context
    // so a final zero-byte callback (some callers rely on it) has the
    // correct total. libcurl has already drained; this is informational.
    curl_off_t cl = 0;
    curl_easy_getinfo(c->curl, CURLINFO_CONTENT_LENGTH_DOWNLOAD_T, &cl);
    if (cl > 0) {
        stream_ctx.content_length = static_cast<uint64_t>(cl);
    }

    fill_response_meta(c->curl, &hdr_ctx, out_resp_meta);
    // Body is delivered via callback — leave body_bytes NULL.

    if (stream_ctx.cancelled) {
        return RAC_ERROR_CANCELLED;
    }
    if (rc != CURLE_OK) {
        return curlcode_to_rac(rc);
    }
    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_http_request_resume(rac_http_client_t* c,
                                                const rac_http_request_t* req,
                                                uint64_t resume_from_byte,
                                                rac_http_body_chunk_fn cb, void* user_data,
                                                rac_http_response_t* out_resp_meta) {
    if (!c || !c->curl || !req || !cb || !out_resp_meta) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    std::memset(out_resp_meta, 0, sizeof(*out_resp_meta));

    curl_slist_owner hdrs_owner;
    rac_result_t setup = validate_and_setup(c->curl, req, &hdrs_owner);
    if (setup != RAC_SUCCESS) {
        return setup;
    }

    // Set Range: bytes=N- via libcurl's native option.
    curl_easy_setopt(c->curl, CURLOPT_RESUME_FROM_LARGE,
                     static_cast<curl_off_t>(resume_from_byte));

    stream_write_ctx stream_ctx{cb, user_data, 0, 0, false};
    header_capture_ctx hdr_ctx;
    curl_easy_setopt(c->curl, CURLOPT_WRITEFUNCTION, write_to_stream);
    curl_easy_setopt(c->curl, CURLOPT_WRITEDATA, &stream_ctx);
    curl_easy_setopt(c->curl, CURLOPT_HEADERFUNCTION, capture_header);
    curl_easy_setopt(c->curl, CURLOPT_HEADERDATA, &hdr_ctx);

    CURLcode rc = curl_easy_perform(c->curl);

    curl_off_t cl = 0;
    curl_easy_getinfo(c->curl, CURLINFO_CONTENT_LENGTH_DOWNLOAD_T, &cl);
    if (cl > 0) {
        stream_ctx.content_length = static_cast<uint64_t>(cl);
    }

    fill_response_meta(c->curl, &hdr_ctx, out_resp_meta);

    if (stream_ctx.cancelled) {
        return RAC_ERROR_CANCELLED;
    }
    if (rc != CURLE_OK) {
        return curlcode_to_rac(rc);
    }
    return RAC_SUCCESS;
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
