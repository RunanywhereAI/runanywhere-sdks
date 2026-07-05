/**
 * @file test_http_upsert_mode.cpp
 * @brief Parity test for `rac_http_request_set_upsert_mode`.
 *
 * Registers a stub `rac_http_transport_ops_t` that captures the URL +
 * headers the request layer hands it, then verifies that:
 *   1. Without arming, the request goes through unchanged.
 *   2. After `rac_http_request_set_upsert_mode(req, "device_id")`, the
 *      adapter sees `?on_conflict=device_id` appended to the URL and a
 *      `Prefer: resolution=merge-duplicates,return=representation`
 *      header.
 *   3. Pre-existing query strings yield `&on_conflict=...`.
 *   4. Pre-existing headers are preserved when the Prefer header is
 *      appended.
 *   5. Calling `set_upsert_mode(req, NULL)` clears prior arming.
 *   6. Arming is single-shot: a second send without re-arming reverts
 *      to the un-rewritten URL/headers.
 *   7. Stream + resume dispatch sites apply the same transform as send.
 */

#include <cstdint>
#include <cstring>
#include <iostream>
#include <string>
#include <utility>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/http/rac_http_transport.h"

namespace {

// =============================================================================
// Capture struct — every adapter call writes the inputs it observed here.
// =============================================================================

struct CaptureState {
    std::string url;
    std::vector<std::pair<std::string, std::string>> headers;
    std::string method;
    std::string body;
    int call_count = 0;
};

CaptureState g_capture;

void reset_capture() {
    g_capture = CaptureState{};
}

// =============================================================================
// Stub adapter — records inputs, returns a synthetic 200 response.
// =============================================================================

void copy_request(const rac_http_request_t* req) {
    g_capture.method = req->method ? req->method : "";
    g_capture.url = req->url ? req->url : "";
    g_capture.headers.clear();
    for (size_t i = 0; i < req->header_count; ++i) {
        g_capture.headers.emplace_back(req->headers[i].name ? req->headers[i].name : "",
                                       req->headers[i].value ? req->headers[i].value : "");
    }
    g_capture.body.assign(reinterpret_cast<const char*>(req->body_bytes),
                          req->body_bytes ? req->body_len : 0);
    ++g_capture.call_count;
}

rac_result_t stub_request_send(void* /*user_data*/, const rac_http_request_t* req,
                               rac_http_response_t* out_resp) {
    copy_request(req);
    out_resp->status = 200;
    return RAC_SUCCESS;
}

rac_result_t stub_request_stream(void* /*user_data*/, const rac_http_request_t* req,
                                 rac_http_body_chunk_fn /*cb*/, void* /*cb_user_data*/,
                                 rac_http_response_t* out_resp_meta) {
    copy_request(req);
    out_resp_meta->status = 200;
    return RAC_SUCCESS;
}

rac_result_t stub_request_resume(void* /*user_data*/, const rac_http_request_t* req,
                                 uint64_t /*resume_from_byte*/, rac_http_body_chunk_fn /*cb*/,
                                 void* /*cb_user_data*/, rac_http_response_t* out_resp_meta) {
    copy_request(req);
    out_resp_meta->status = 206;
    return RAC_SUCCESS;
}

const rac_http_transport_ops_t kStubOps = {
    /*request_send=*/stub_request_send,
    /*request_stream=*/stub_request_stream,
    /*request_resume=*/stub_request_resume,
    /*init=*/nullptr,
    /*destroy=*/nullptr,
};

// =============================================================================
// Tiny assert machinery (mirrors test_http_client.cpp).
// =============================================================================

int g_failures = 0;
int g_passes = 0;

#define CHECK(cond)                                                                       \
    do {                                                                                  \
        if (cond) {                                                                       \
            ++g_passes;                                                                   \
        } else {                                                                          \
            ++g_failures;                                                                 \
            std::cerr << "[FAIL] " << __FILE__ << ":" << __LINE__ << " - " #cond << "\n"; \
        }                                                                                 \
    } while (0)

#define CHECK_EQ_I(a, b)                                                                         \
    do {                                                                                         \
        auto _a = (a);                                                                           \
        auto _b = (b);                                                                           \
        if (_a == _b) {                                                                          \
            ++g_passes;                                                                          \
        } else {                                                                                 \
            ++g_failures;                                                                        \
            std::cerr << "[FAIL] " << __FILE__ << ":" << __LINE__ << " - " #a " == " #b " (got " \
                      << _a << " vs " << _b << ")\n";                                            \
        }                                                                                        \
    } while (0)

#define CHECK_EQ_S(a, b)                                                                          \
    do {                                                                                          \
        std::string _a = (a);                                                                     \
        std::string _b = (b);                                                                     \
        if (_a == _b) {                                                                           \
            ++g_passes;                                                                           \
        } else {                                                                                  \
            ++g_failures;                                                                         \
            std::cerr << "[FAIL] " << __FILE__ << ":" << __LINE__ << " - " #a " == " #b " (got '" \
                      << _a << "' vs '" << _b << "')\n";                                          \
        }                                                                                         \
    } while (0)

bool find_header(const std::string& name, std::string* value_out) {
    for (auto& kv : g_capture.headers) {
        if (kv.first == name) {
            if (value_out)
                *value_out = kv.second;
            return true;
        }
    }
    return false;
}

// =============================================================================
// Helpers: build a stock POST request descriptor.
// =============================================================================

rac_http_request_t make_request(const char* url, const rac_http_header_kv_t* headers,
                                size_t header_count, const char* body) {
    rac_http_request_t req{};
    req.method = "POST";
    req.url = url;
    req.headers = headers;
    req.header_count = header_count;
    req.body_bytes = body ? reinterpret_cast<const uint8_t*>(body) : nullptr;
    req.body_len = body ? std::strlen(body) : 0;
    req.timeout_ms = 5000;
    req.follow_redirects = RAC_FALSE;
    req.expected_checksum_hex = nullptr;
    return req;
}

// =============================================================================
// Tests
// =============================================================================

void test_passthrough_when_not_armed() {
    reset_capture();
    rac_http_client_t* client = nullptr;
    CHECK_EQ_I(rac_http_client_create(&client), RAC_SUCCESS);

    rac_http_request_t req = make_request("https://example.test/devices", nullptr, 0, "{}");
    rac_http_response_t resp{};
    CHECK_EQ_I(rac_http_request_send(client, &req, &resp), RAC_SUCCESS);

    // URL untouched, no Prefer header.
    CHECK_EQ_S(g_capture.url, "https://example.test/devices");
    CHECK(!find_header("Prefer", nullptr));
    CHECK_EQ_I(g_capture.headers.size(), size_t{0});

    rac_http_response_free(&resp);
    rac_http_client_destroy(client);
}

void test_upsert_simple_url_no_query() {
    reset_capture();
    rac_http_client_t* client = nullptr;
    rac_http_client_create(&client);

    rac_http_request_t req = make_request("https://example.test/devices", nullptr, 0, "{}");
    CHECK_EQ_I(rac_http_request_set_upsert_mode(&req, "device_id"), RAC_SUCCESS);

    rac_http_response_t resp{};
    CHECK_EQ_I(rac_http_request_send(client, &req, &resp), RAC_SUCCESS);

    // URL gets `?on_conflict=device_id`.
    CHECK_EQ_S(g_capture.url, "https://example.test/devices?on_conflict=device_id");

    // Prefer header set with the canonical Supabase value.
    std::string prefer_value;
    CHECK(find_header("Prefer", &prefer_value));
    CHECK_EQ_S(prefer_value, "resolution=merge-duplicates,return=representation");

    rac_http_response_free(&resp);
    rac_http_client_destroy(client);
}

void test_upsert_url_with_existing_query() {
    reset_capture();
    rac_http_client_t* client = nullptr;
    rac_http_client_create(&client);

    // Pre-existing `?select=*` — upsert must use `&` not `?`.
    rac_http_request_t req =
        make_request("https://example.test/devices?select=*", nullptr, 0, "{}");
    rac_http_request_set_upsert_mode(&req, "device_id");

    rac_http_response_t resp{};
    rac_http_request_send(client, &req, &resp);

    CHECK_EQ_S(g_capture.url, "https://example.test/devices?select=*&on_conflict=device_id");

    rac_http_response_free(&resp);
    rac_http_client_destroy(client);
}

void test_upsert_preserves_existing_headers() {
    reset_capture();
    rac_http_client_t* client = nullptr;
    rac_http_client_create(&client);

    rac_http_header_kv_t hs[2] = {
        {"Content-Type", "application/json"},
        {"X-API-Key", "secret-token"},
    };
    rac_http_request_t req = make_request("https://example.test/devices", hs, 2, "{}");
    rac_http_request_set_upsert_mode(&req, "device_id");

    rac_http_response_t resp{};
    rac_http_request_send(client, &req, &resp);

    // Original headers must survive...
    std::string ct, key;
    CHECK(find_header("Content-Type", &ct));
    CHECK_EQ_S(ct, "application/json");
    CHECK(find_header("X-API-Key", &key));
    CHECK_EQ_S(key, "secret-token");

    // ...and Prefer is appended.
    std::string prefer_value;
    CHECK(find_header("Prefer", &prefer_value));
    CHECK_EQ_S(prefer_value, "resolution=merge-duplicates,return=representation");

    // 2 original + 1 Prefer = 3 headers visible to the adapter.
    CHECK_EQ_I(g_capture.headers.size(), size_t{3});

    rac_http_response_free(&resp);
    rac_http_client_destroy(client);
}

void test_upsert_clear_with_null() {
    reset_capture();
    rac_http_client_t* client = nullptr;
    rac_http_client_create(&client);

    rac_http_request_t req = make_request("https://example.test/devices", nullptr, 0, "{}");
    // Arm then clear.
    CHECK_EQ_I(rac_http_request_set_upsert_mode(&req, "device_id"), RAC_SUCCESS);
    CHECK_EQ_I(rac_http_request_set_upsert_mode(&req, nullptr), RAC_SUCCESS);

    rac_http_response_t resp{};
    rac_http_request_send(client, &req, &resp);

    // No transform should have been applied.
    CHECK_EQ_S(g_capture.url, "https://example.test/devices");
    CHECK(!find_header("Prefer", nullptr));

    rac_http_response_free(&resp);
    rac_http_client_destroy(client);
}

void test_upsert_is_single_shot() {
    reset_capture();
    rac_http_client_t* client = nullptr;
    rac_http_client_create(&client);

    rac_http_request_t req = make_request("https://example.test/devices", nullptr, 0, "{}");
    rac_http_request_set_upsert_mode(&req, "device_id");

    // First send — transform applies.
    rac_http_response_t r1{};
    rac_http_request_send(client, &req, &r1);
    CHECK_EQ_S(g_capture.url, "https://example.test/devices?on_conflict=device_id");
    CHECK(find_header("Prefer", nullptr));
    rac_http_response_free(&r1);

    // Second send without re-arming — the per-request flag has been consumed.
    reset_capture();
    rac_http_response_t r2{};
    rac_http_request_send(client, &req, &r2);
    CHECK_EQ_S(g_capture.url, "https://example.test/devices");
    CHECK(!find_header("Prefer", nullptr));
    rac_http_response_free(&r2);

    rac_http_client_destroy(client);
}

void test_upsert_invalid_args() {
    CHECK_EQ_I(rac_http_request_set_upsert_mode(nullptr, "device_id"), RAC_ERROR_INVALID_ARGUMENT);
}

void test_upsert_applied_in_stream() {
    reset_capture();
    rac_http_client_t* client = nullptr;
    rac_http_client_create(&client);

    rac_http_request_t req = make_request("https://example.test/devices", nullptr, 0, "{}");
    rac_http_request_set_upsert_mode(&req, "device_id");

    auto cb = [](const uint8_t*, size_t, uint64_t, uint64_t, void*) -> rac_bool_t {
        return RAC_TRUE;
    };

    rac_http_response_t resp{};
    rac_http_request_stream(client, &req, cb, nullptr, &resp);
    CHECK_EQ_S(g_capture.url, "https://example.test/devices?on_conflict=device_id");
    CHECK(find_header("Prefer", nullptr));

    rac_http_response_free(&resp);
    rac_http_client_destroy(client);
}

void test_upsert_applied_in_resume() {
    reset_capture();
    rac_http_client_t* client = nullptr;
    rac_http_client_create(&client);

    rac_http_request_t req = make_request("https://example.test/devices", nullptr, 0, "{}");
    rac_http_request_set_upsert_mode(&req, "device_id");

    auto cb = [](const uint8_t*, size_t, uint64_t, uint64_t, void*) -> rac_bool_t {
        return RAC_TRUE;
    };

    rac_http_response_t resp{};
    rac_http_request_resume(client, &req, /*resume_from_byte=*/0, cb, nullptr, &resp);
    CHECK_EQ_S(g_capture.url, "https://example.test/devices?on_conflict=device_id");
    CHECK(find_header("Prefer", nullptr));

    rac_http_response_free(&resp);
    rac_http_client_destroy(client);
}

}  // namespace

int main() {
    std::cout << "=== rac_http_request_set_upsert_mode tests ===\n";

    if (rac_http_transport_register(&kStubOps, /*user_data=*/nullptr) != RAC_SUCCESS) {
        std::cerr << "failed to register stub HTTP transport\n";
        return 1;
    }

    test_passthrough_when_not_armed();
    test_upsert_simple_url_no_query();
    test_upsert_url_with_existing_query();
    test_upsert_preserves_existing_headers();
    test_upsert_clear_with_null();
    test_upsert_is_single_shot();
    test_upsert_invalid_args();
    test_upsert_applied_in_stream();
    test_upsert_applied_in_resume();

    // Unregister so we don't leak the stub vtable into any later tests.
    rac_http_transport_register(nullptr, nullptr);

    std::cout << "passes=" << g_passes << " failures=" << g_failures << "\n";
    return g_failures == 0 ? 0 : 1;
}
