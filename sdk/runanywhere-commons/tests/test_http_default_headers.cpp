/**
 * @file test_http_default_headers.cpp
 * @brief Parity test for `rac_http_default_headers`.
 *
 * Verifies that the canonical default-header list returned from commons
 * matches Swift's `HTTPClientAdapter.defaultHeaders` (sans X-Platform):
 *
 *   - "X-SDK-Client":  "RunAnywhereSDK"
 *   - "X-SDK-Version": rac_get_version().string
 *   - "Content-Type":  "application/json"
 *   - "Accept":        "application/json"
 *
 * Also asserts:
 *   - X-Platform is NOT in the returned set (callers add it per-request).
 *   - The same pointer is returned across calls (statically allocated).
 *   - NULL out-pointers are rejected with RAC_ERROR_INVALID_ARGUMENT.
 */

#include "test_common.h"

#include <cstddef>
#include <cstring>
#include <iostream>
#include <map>
#include <string>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/http/rac_http_client.h"

namespace {

std::map<std::string, std::string> to_map(const rac_http_header_kv_t* kvs, size_t count) {
    std::map<std::string, std::string> out;
    for (size_t i = 0; i < count; ++i) {
        out[std::string(kvs[i].name ? kvs[i].name : "")] =
            std::string(kvs[i].value ? kvs[i].value : "");
    }
    return out;
}

TestResult test_canonical_content_matches_swift() {
    const rac_http_header_kv_t* kvs = nullptr;
    size_t count = 0;
    rac_result_t rc = rac_http_default_headers(&kvs, &count);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_http_default_headers should succeed");
    ASSERT_TRUE(kvs != nullptr, "kvs out-pointer should be non-NULL");
    ASSERT_TRUE(count >= 4, "should return at least 4 canonical headers");

    auto map = to_map(kvs, count);

    // Canonical content (mirrors Swift's HTTPClientAdapter.defaultHeaders).
    auto sdk_client = map.find("X-SDK-Client");
    ASSERT_TRUE(sdk_client != map.end(), "X-SDK-Client must be present");
    ASSERT_TRUE(sdk_client->second == "RunAnywhereSDK", "X-SDK-Client must equal RunAnywhereSDK");

    auto sdk_version = map.find("X-SDK-Version");
    ASSERT_TRUE(sdk_version != map.end(), "X-SDK-Version must be present");
    ASSERT_TRUE(!sdk_version->second.empty(), "X-SDK-Version must be non-empty");

    // X-SDK-Version must mirror rac_get_version().string exactly.
    rac_version_t v = rac_get_version();
    ASSERT_TRUE(v.string != nullptr, "rac_get_version().string must be non-NULL");
    ASSERT_TRUE(sdk_version->second == std::string(v.string),
                "X-SDK-Version must equal rac_get_version().string");

    auto content_type = map.find("Content-Type");
    ASSERT_TRUE(content_type != map.end(), "Content-Type must be present");
    ASSERT_TRUE(content_type->second == "application/json",
                "Content-Type must equal application/json");

    auto accept = map.find("Accept");
    ASSERT_TRUE(accept != map.end(), "Accept must be present");
    ASSERT_TRUE(accept->second == "application/json", "Accept must equal application/json");

    return TEST_PASS();
}

TestResult test_x_platform_not_included() {
    const rac_http_header_kv_t* kvs = nullptr;
    size_t count = 0;
    rac_result_t rc = rac_http_default_headers(&kvs, &count);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_http_default_headers should succeed");

    for (size_t i = 0; i < count; ++i) {
        const char* name = kvs[i].name;
        ASSERT_TRUE(name != nullptr, "header name must be non-NULL");
        // Defensive case-insensitive compare — the platform header must
        // NOT appear under any casing.
        ASSERT_TRUE(std::strlen(name) > 0, "header name must be non-empty");
        bool is_platform = (std::strcmp(name, "X-Platform") == 0) ||
                           (std::strcmp(name, "x-platform") == 0) ||
                           (std::strcmp(name, "X-PLATFORM") == 0);
        ASSERT_TRUE(!is_platform, "X-Platform must not be in the default header list");
    }

    return TEST_PASS();
}

TestResult test_same_pointer_across_calls() {
    const rac_http_header_kv_t* first = nullptr;
    size_t first_count = 0;
    rac_result_t rc1 = rac_http_default_headers(&first, &first_count);
    ASSERT_EQ(rc1, RAC_SUCCESS, "first call should succeed");

    const rac_http_header_kv_t* second = nullptr;
    size_t second_count = 0;
    rac_result_t rc2 = rac_http_default_headers(&second, &second_count);
    ASSERT_EQ(rc2, RAC_SUCCESS, "second call should succeed");

    ASSERT_TRUE(first == second, "same array pointer must be returned across calls");
    ASSERT_EQ(first_count, second_count, "same count must be returned across calls");

    // Field pointers themselves are static-storage-duration too.
    for (size_t i = 0; i < first_count; ++i) {
        ASSERT_TRUE(first[i].name == second[i].name,
                    "header name pointer must be stable across calls");
        ASSERT_TRUE(first[i].value == second[i].value,
                    "header value pointer must be stable across calls");
    }

    return TEST_PASS();
}

TestResult test_null_out_pointers_rejected() {
    const rac_http_header_kv_t* kvs = nullptr;
    size_t count = 0;

    rac_result_t rc_null_kvs = rac_http_default_headers(nullptr, &count);
    ASSERT_EQ(rc_null_kvs, RAC_ERROR_INVALID_ARGUMENT, "NULL out_kvs must be rejected");

    rac_result_t rc_null_count = rac_http_default_headers(&kvs, nullptr);
    ASSERT_EQ(rc_null_count, RAC_ERROR_INVALID_ARGUMENT, "NULL out_count must be rejected");

    rac_result_t rc_both_null = rac_http_default_headers(nullptr, nullptr);
    ASSERT_EQ(rc_both_null, RAC_ERROR_INVALID_ARGUMENT, "both NULL must be rejected");

    return TEST_PASS();
}

}  // namespace

int main(int argc, char** argv) {
    TestSuite suite("http_default_headers");
    suite.add("canonical_content_matches_swift", test_canonical_content_matches_swift);
    suite.add("x_platform_not_included", test_x_platform_not_included);
    suite.add("same_pointer_across_calls", test_same_pointer_across_calls);
    suite.add("null_out_pointers_rejected", test_null_out_pointers_rejected);
    return suite.run(argc, argv);
}
