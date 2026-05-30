/**
 * @file test_device_identity.cpp
 * @brief Unit tests for rac_device_get_or_create_persistent_id.
 *
 * Mocks the rac_platform_adapter_t secure_get / secure_set / get_vendor_id
 * slots and exercises every branch of the resolution chain. Mirrors the test
 * surface each platform SDK had previously implemented locally.
 */

#include "test_common.h"

#include <atomic>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <set>
#include <string>
#include <thread>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/device/rac_device_identity.h"

namespace {

// =============================================================================
// Mock platform adapter shared state
// =============================================================================

struct MockAdapterState {
    std::mutex mutex;

    // secure storage
    bool has_stored = false;
    std::string stored;
    int secure_get_calls = 0;
    int secure_set_calls = 0;

    // vendor id
    bool vendor_id_enabled = false;
    std::string vendor_id;
    int vendor_id_calls = 0;
    rac_result_t vendor_id_result = RAC_SUCCESS;

    // simulated secure_set failure
    rac_result_t secure_set_result = RAC_SUCCESS;
};

MockAdapterState g_mock;

void mock_reset() {
    std::lock_guard<std::mutex> lock(g_mock.mutex);
    g_mock.has_stored = false;
    g_mock.stored.clear();
    g_mock.secure_get_calls = 0;
    g_mock.secure_set_calls = 0;
    g_mock.vendor_id_enabled = false;
    g_mock.vendor_id.clear();
    g_mock.vendor_id_calls = 0;
    g_mock.vendor_id_result = RAC_SUCCESS;
    g_mock.secure_set_result = RAC_SUCCESS;
}

// Canonical device-UUID secure-storage key shared with Swift KeychainManager
// (`com.runanywhere.sdk.device.uuid`). Must stay in sync with kSecureStorageKey
// in device_identity.cpp.
constexpr const char* kDeviceIdKey = "com.runanywhere.sdk.device.uuid";

rac_result_t mock_secure_get(const char* key, char** out_value, void* /*user_data*/) {
    std::lock_guard<std::mutex> lock(g_mock.mutex);
    g_mock.secure_get_calls++;
    if (key == nullptr || std::strcmp(key, kDeviceIdKey) != 0) {
        if (out_value)
            *out_value = nullptr;
        return RAC_ERROR_NOT_FOUND;
    }
    if (!g_mock.has_stored) {
        if (out_value)
            *out_value = nullptr;
        return RAC_ERROR_NOT_FOUND;
    }
    if (out_value) {
        *out_value = strdup(g_mock.stored.c_str());
        if (*out_value == nullptr)
            return RAC_ERROR_OUT_OF_MEMORY;
    }
    return RAC_SUCCESS;
}

rac_result_t mock_secure_set(const char* key, const char* value, void* /*user_data*/) {
    std::lock_guard<std::mutex> lock(g_mock.mutex);
    g_mock.secure_set_calls++;
    if (key == nullptr || std::strcmp(key, kDeviceIdKey) != 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (g_mock.secure_set_result != RAC_SUCCESS) {
        return g_mock.secure_set_result;
    }
    g_mock.stored = (value != nullptr) ? std::string(value) : std::string();
    g_mock.has_stored = true;
    return RAC_SUCCESS;
}

rac_result_t mock_secure_delete(const char* /*key*/, void* /*user_data*/) {
    return RAC_SUCCESS;
}

rac_result_t mock_get_vendor_id(char* out_buffer, size_t buffer_size, void* /*user_data*/) {
    std::lock_guard<std::mutex> lock(g_mock.mutex);
    g_mock.vendor_id_calls++;
    if (g_mock.vendor_id_result != RAC_SUCCESS) {
        return g_mock.vendor_id_result;
    }
    if (out_buffer == nullptr || buffer_size < g_mock.vendor_id.size() + 1) {
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }
    std::memcpy(out_buffer, g_mock.vendor_id.data(), g_mock.vendor_id.size());
    out_buffer[g_mock.vendor_id.size()] = '\0';
    return RAC_SUCCESS;
}

void install_adapter(bool with_vendor_id) {
    static rac_platform_adapter_t adapter;
    std::memset(&adapter, 0, sizeof(adapter));
    adapter.secure_get = &mock_secure_get;
    adapter.secure_set = &mock_secure_set;
    adapter.secure_delete = &mock_secure_delete;
    if (with_vendor_id) {
        adapter.get_vendor_id = &mock_get_vendor_id;
    }
    adapter.user_data = nullptr;
    rac_set_platform_adapter(&adapter);
}

void clear_adapter() {
    rac_set_platform_adapter(nullptr);
}

void prepare(bool with_vendor_id) {
    rac_device_identity_reset_cache_for_testing();
    mock_reset();
    install_adapter(with_vendor_id);
}

bool looks_like_uuid(const std::string& s) {
    if (s.size() != 36)
        return false;
    for (size_t i = 0; i < s.size(); ++i) {
        char c = s[i];
        if (i == 8 || i == 13 || i == 18 || i == 23) {
            if (c != '-')
                return false;
        } else {
            const bool is_hex =
                (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
            if (!is_hex)
                return false;
        }
    }
    return true;
}

// =============================================================================
// Test cases
// =============================================================================

TestResult test_secure_get_hit() {
    prepare(/*with_vendor_id=*/true);
    {
        std::lock_guard<std::mutex> lock(g_mock.mutex);
        g_mock.has_stored = true;
        g_mock.stored = "cached-uuid-12345";
        g_mock.vendor_id = "vendor-should-not-be-used";
    }

    char buf[64] = {0};
    rac_result_t rc = rac_device_get_or_create_persistent_id(buf, sizeof(buf));
    ASSERT_EQ(rc, RAC_SUCCESS, "expected RAC_SUCCESS on cache hit");
    ASSERT_TRUE(std::string(buf) == "cached-uuid-12345",
                std::string("expected cached id, got: ") + buf);

    {
        std::lock_guard<std::mutex> lock(g_mock.mutex);
        ASSERT_EQ(g_mock.secure_get_calls, 1, "secure_get should be called exactly once");
        ASSERT_EQ(g_mock.vendor_id_calls, 0, "vendor_id MUST NOT be called on hit");
        ASSERT_EQ(g_mock.secure_set_calls, 0, "secure_set MUST NOT be called on hit");
    }
    clear_adapter();
    return TEST_PASS();
}

TestResult test_secure_get_miss_vendor_id_present() {
    prepare(/*with_vendor_id=*/true);
    {
        std::lock_guard<std::mutex> lock(g_mock.mutex);
        g_mock.has_stored = false;
        g_mock.vendor_id = "ABCDEF01-2345-6789-ABCD-EF0123456789";
    }

    char buf[64] = {0};
    rac_result_t rc = rac_device_get_or_create_persistent_id(buf, sizeof(buf));
    ASSERT_EQ(rc, RAC_SUCCESS, "expected RAC_SUCCESS on vendor-id branch");
    ASSERT_TRUE(std::string(buf) == "ABCDEF01-2345-6789-ABCD-EF0123456789",
                std::string("expected vendor id, got: ") + buf);

    {
        std::lock_guard<std::mutex> lock(g_mock.mutex);
        ASSERT_EQ(g_mock.secure_get_calls, 1, "secure_get should be called once");
        ASSERT_EQ(g_mock.vendor_id_calls, 1, "vendor_id should be called once");
        ASSERT_EQ(g_mock.secure_set_calls, 1, "secure_set should persist the vendor id");
        ASSERT_TRUE(g_mock.has_stored, "secure storage should now be populated");
        ASSERT_TRUE(g_mock.stored == "ABCDEF01-2345-6789-ABCD-EF0123456789",
                    "secure storage should hold the vendor id");
    }
    clear_adapter();
    return TEST_PASS();
}

TestResult test_secure_get_miss_no_vendor_id_generates_uuid() {
    prepare(/*with_vendor_id=*/false);  // get_vendor_id slot is NULL

    char buf[64] = {0};
    rac_result_t rc = rac_device_get_or_create_persistent_id(buf, sizeof(buf));
    ASSERT_EQ(rc, RAC_SUCCESS, "expected RAC_SUCCESS on synth path");
    const std::string id(buf);
    ASSERT_TRUE(looks_like_uuid(id), std::string("expected canonical UUID v4, got: ") + id);

    {
        std::lock_guard<std::mutex> lock(g_mock.mutex);
        ASSERT_EQ(g_mock.secure_get_calls, 1, "secure_get should be called once");
        ASSERT_EQ(g_mock.vendor_id_calls, 0, "vendor_id MUST NOT be called when slot is NULL");
        ASSERT_EQ(g_mock.secure_set_calls, 1, "secure_set should persist the synth id");
        ASSERT_TRUE(g_mock.stored == id, "secure storage should hold the synthesized id");
        // Verify version-4 nibble.
        ASSERT_TRUE(id[14] == '4', std::string("expected v4 nibble at index 14, got: ") + id);
    }
    clear_adapter();
    return TEST_PASS();
}

TestResult test_concurrent_calls_return_same_id() {
    prepare(/*with_vendor_id=*/false);

    constexpr int kThreads = 8;
    std::vector<std::thread> threads;
    std::vector<std::string> results(kThreads);
    std::atomic<int> ready{0};

    for (int i = 0; i < kThreads; ++i) {
        threads.emplace_back([&, i]() {
            ready.fetch_add(1);
            // Spin a touch so threads enter the function near-simultaneously.
            while (ready.load() < kThreads) {
                std::this_thread::yield();
            }
            char local[64] = {0};
            rac_result_t rc = rac_device_get_or_create_persistent_id(local, sizeof(local));
            if (rc == RAC_SUCCESS) {
                results[i].assign(local);
            }
        });
    }
    for (auto& t : threads)
        t.join();

    std::set<std::string> distinct(results.begin(), results.end());
    ASSERT_EQ(distinct.size(), 1u, "concurrent callers MUST observe the same persistent id");
    ASSERT_TRUE(!results[0].empty(), "first thread must have populated a result");

    clear_adapter();
    return TEST_PASS();
}

TestResult test_null_out_rejected() {
    prepare(/*with_vendor_id=*/false);
    rac_result_t rc = rac_device_get_or_create_persistent_id(nullptr, 64);
    ASSERT_EQ(rc, RAC_ERROR_NULL_POINTER, "NULL out must return RAC_ERROR_NULL_POINTER");
    clear_adapter();
    return TEST_PASS();
}

TestResult test_buffer_too_small_rejected() {
    prepare(/*with_vendor_id=*/false);
    char small[16] = {0};
    rac_result_t rc = rac_device_get_or_create_persistent_id(small, sizeof(small));
    ASSERT_EQ(rc, RAC_ERROR_BUFFER_TOO_SMALL,
              "out_size < 37 must return RAC_ERROR_BUFFER_TOO_SMALL");
    {
        std::lock_guard<std::mutex> lock(g_mock.mutex);
        ASSERT_EQ(g_mock.secure_get_calls, 0,
                  "size validation must short-circuit before adapter calls");
        ASSERT_EQ(g_mock.secure_set_calls, 0,
                  "size validation must short-circuit before adapter calls");
    }
    clear_adapter();
    return TEST_PASS();
}

TestResult test_empty_adapter_falls_through_to_uuid() {
    // Adapter installed, but every platform-supplied callback is NULL.
    // The chain must skip secure_get / vendor_id and synthesize a UUID
    // (without persisting it back, since secure_set is also NULL).
    rac_device_identity_reset_cache_for_testing();
    mock_reset();
    static rac_platform_adapter_t empty_adapter;
    std::memset(&empty_adapter, 0, sizeof(empty_adapter));
    rac_set_platform_adapter(&empty_adapter);

    char buf[64] = {0};
    rac_result_t rc = rac_device_get_or_create_persistent_id(buf, sizeof(buf));
    ASSERT_EQ(rc, RAC_SUCCESS, "empty adapter must still yield a UUID");
    ASSERT_TRUE(looks_like_uuid(std::string(buf)),
                std::string("expected canonical UUID v4, got: ") + buf);
    return TEST_PASS();
}

}  // namespace

int main(int argc, char** argv) {
    TestSuite suite("device_identity");
    suite.add("secure_get_hit", test_secure_get_hit);
    suite.add("secure_get_miss_vendor_id_present", test_secure_get_miss_vendor_id_present);
    suite.add("secure_get_miss_no_vendor_id_generates_uuid",
              test_secure_get_miss_no_vendor_id_generates_uuid);
    suite.add("concurrent_calls_return_same_id", test_concurrent_calls_return_same_id);
    suite.add("null_out_rejected", test_null_out_rejected);
    suite.add("buffer_too_small_rejected", test_buffer_too_small_rejected);
    suite.add("empty_adapter_falls_through_to_uuid", test_empty_adapter_falls_through_to_uuid);
    return suite.run(argc, argv);
}
