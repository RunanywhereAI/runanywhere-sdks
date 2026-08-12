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
    rac_result_t secure_get_result = RAC_SUCCESS;
    bool secure_get_success_null = false;

    // vendor id
    bool vendor_id_enabled = false;
    std::string vendor_id;
    int vendor_id_calls = 0;
    rac_result_t vendor_id_result = RAC_SUCCESS;

    // simulated secure_set failure
    rac_result_t secure_set_result = RAC_SUCCESS;
};

MockAdapterState g_mock;
rac_platform_adapter_t g_adapter;

void mock_reset() {
    std::lock_guard<std::mutex> lock(g_mock.mutex);
    g_mock.has_stored = false;
    g_mock.stored.clear();
    g_mock.secure_get_calls = 0;
    g_mock.secure_set_calls = 0;
    g_mock.secure_get_result = RAC_SUCCESS;
    g_mock.secure_get_success_null = false;
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
        return RAC_ERROR_FILE_NOT_FOUND;
    }
    if (g_mock.secure_get_result != RAC_SUCCESS) {
        if (out_value)
            *out_value = nullptr;
        return g_mock.secure_get_result;
    }
    if (g_mock.secure_get_success_null) {
        if (out_value)
            *out_value = nullptr;
        return RAC_SUCCESS;
    }
    if (!g_mock.has_stored) {
        if (out_value)
            *out_value = nullptr;
        return RAC_ERROR_FILE_NOT_FOUND;
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
    std::memset(&g_adapter, 0, sizeof(g_adapter));
    g_adapter.secure_get = &mock_secure_get;
    g_adapter.secure_set = &mock_secure_set;
    g_adapter.secure_delete = &mock_secure_delete;
    if (with_vendor_id) {
        g_adapter.get_vendor_id = &mock_get_vendor_id;
    }
    g_adapter.user_data = nullptr;
    rac_set_platform_adapter(&g_adapter);
}

void clear_adapter() {
    rac_set_platform_adapter(nullptr);
}

void prepare(bool with_vendor_id) {
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
        g_mock.stored = "12345678-1234-4567-89AB-123456789ABC";
        g_mock.vendor_id = "vendor-should-not-be-used";
    }

    char buf[64] = {0};
    rac_result_t rc = rac_device_get_or_create_persistent_id(buf, sizeof(buf));
    ASSERT_EQ(rc, RAC_SUCCESS, "expected RAC_SUCCESS on cache hit");
    ASSERT_TRUE(std::string(buf) == "12345678-1234-4567-89AB-123456789ABC",
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

TestResult test_durable_hit_does_not_mask_later_read_failure() {
    prepare(/*with_vendor_id=*/false);
    {
        std::lock_guard<std::mutex> lock(g_mock.mutex);
        g_mock.has_stored = true;
        g_mock.stored = "12345678-1234-4567-89AB-123456789ABC";
    }

    char buf[64] = {0};
    ASSERT_EQ(rac_device_get_or_create_persistent_id(buf, sizeof(buf)), RAC_SUCCESS,
              "initial durable identity read should succeed");
    {
        std::lock_guard<std::mutex> lock(g_mock.mutex);
        g_mock.secure_get_result = RAC_ERROR_SECURE_STORAGE_FAILED;
    }

    std::strcpy(buf, "sentinel");
    ASSERT_EQ(rac_device_get_or_create_persistent_id(buf, sizeof(buf)),
              RAC_ERROR_SECURE_STORAGE_FAILED,
              "later secure-storage failure must not use process-local identity state");
    ASSERT_TRUE(buf[0] == '\0', "read failure must clear the output buffer");
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

TestResult test_vendor_id_write_failure_is_not_returned_or_cached() {
    prepare(/*with_vendor_id=*/true);
    {
        std::lock_guard<std::mutex> lock(g_mock.mutex);
        g_mock.vendor_id = "ABCDEF01-2345-6789-ABCD-EF0123456789";
        g_mock.secure_set_result = RAC_ERROR_PERMISSION_DENIED;
    }

    char buf[64] = "sentinel";
    rac_result_t rc = rac_device_get_or_create_persistent_id(buf, sizeof(buf));
    ASSERT_EQ(rc, RAC_ERROR_PERMISSION_DENIED, "vendor-id persistence failure must propagate");
    ASSERT_TRUE(buf[0] == '\0', "failed vendor id must not be returned");

    {
        std::lock_guard<std::mutex> lock(g_mock.mutex);
        ASSERT_EQ(g_mock.secure_set_calls, 1, "vendor id should attempt one secure write");
        ASSERT_TRUE(!g_mock.has_stored, "failed vendor id must not appear persisted");
        g_mock.secure_get_result = RAC_ERROR_SECURE_STORAGE_FAILED;
        g_mock.secure_set_result = RAC_SUCCESS;
    }

    std::strcpy(buf, "sentinel");
    rc = rac_device_get_or_create_persistent_id(buf, sizeof(buf));
    ASSERT_EQ(rc, RAC_ERROR_SECURE_STORAGE_FAILED,
              "failed vendor id must not survive a later storage failure");
    ASSERT_TRUE(buf[0] == '\0', "cached vendor id must remain unavailable after write failure");
    clear_adapter();
    return TEST_PASS();
}

TestResult test_generated_uuid_write_failure_is_not_returned_or_cached() {
    prepare(/*with_vendor_id=*/false);
    {
        std::lock_guard<std::mutex> lock(g_mock.mutex);
        g_mock.secure_set_result = RAC_ERROR_SECURE_STORAGE_FAILED;
    }

    char buf[64] = "sentinel";
    rac_result_t rc = rac_device_get_or_create_persistent_id(buf, sizeof(buf));
    ASSERT_EQ(rc, RAC_ERROR_SECURE_STORAGE_FAILED,
              "generated-UUID persistence failure must propagate");
    ASSERT_TRUE(buf[0] == '\0', "failed generated UUID must not be returned");

    {
        std::lock_guard<std::mutex> lock(g_mock.mutex);
        ASSERT_EQ(g_mock.secure_set_calls, 1, "generated UUID should attempt one secure write");
        ASSERT_TRUE(!g_mock.has_stored, "failed generated UUID must not appear persisted");
        g_mock.secure_get_result = RAC_ERROR_PERMISSION_DENIED;
        g_mock.secure_set_result = RAC_SUCCESS;
    }

    std::strcpy(buf, "sentinel");
    rc = rac_device_get_or_create_persistent_id(buf, sizeof(buf));
    ASSERT_EQ(rc, RAC_ERROR_PERMISSION_DENIED,
              "failed generated UUID must not survive a later storage failure");
    ASSERT_TRUE(buf[0] == '\0',
                "cached generated UUID must remain unavailable after write failure");
    clear_adapter();
    return TEST_PASS();
}

TestResult test_noncanonical_not_found_fails_closed() {
    prepare(/*with_vendor_id=*/false);
    {
        std::lock_guard<std::mutex> lock(g_mock.mutex);
        g_mock.secure_get_result = RAC_ERROR_NOT_FOUND;
    }

    char buf[64] = "sentinel";
    const rac_result_t rc = rac_device_get_or_create_persistent_id(buf, sizeof(buf));
    ASSERT_EQ(rc, RAC_ERROR_NOT_FOUND,
              "only RAC_ERROR_FILE_NOT_FOUND may trigger identity creation");
    ASSERT_TRUE(buf[0] == '\0', "noncanonical misses must not return an identity");
    {
        std::lock_guard<std::mutex> lock(g_mock.mutex);
        ASSERT_EQ(g_mock.secure_set_calls, 0,
                  "noncanonical misses must not create persistent state");
    }
    clear_adapter();
    return TEST_PASS();
}

TestResult test_secure_get_success_with_null_value_fails_closed() {
    prepare(/*with_vendor_id=*/false);
    {
        std::lock_guard<std::mutex> lock(g_mock.mutex);
        g_mock.secure_get_success_null = true;
    }

    char buf[64] = "sentinel";
    const rac_result_t rc = rac_device_get_or_create_persistent_id(buf, sizeof(buf));
    ASSERT_EQ(rc, RAC_ERROR_SECURE_STORAGE_FAILED,
              "RAC_SUCCESS with a null value violates the secure-storage contract");
    ASSERT_TRUE(buf[0] == '\0', "null secure-storage values must not return an identity");
    {
        std::lock_guard<std::mutex> lock(g_mock.mutex);
        ASSERT_EQ(g_mock.secure_set_calls, 0,
                  "null secure-storage values must not create persistent state");
    }
    clear_adapter();
    return TEST_PASS();
}

TestResult test_malformed_stored_id_fails_closed() {
    prepare(/*with_vendor_id=*/true);
    {
        std::lock_guard<std::mutex> lock(g_mock.mutex);
        g_mock.has_stored = true;
        g_mock.stored = "not-a-canonical-uuid";
        g_mock.vendor_id = "ABCDEF01-2345-6789-ABCD-EF0123456789";
    }

    char buf[64] = "sentinel";
    const rac_result_t rc = rac_device_get_or_create_persistent_id(buf, sizeof(buf));
    ASSERT_EQ(rc, RAC_ERROR_SECURE_STORAGE_FAILED,
              "malformed durable identities must fail as corrupted secure storage");
    ASSERT_TRUE(buf[0] == '\0', "malformed durable identities must not be returned");
    {
        std::lock_guard<std::mutex> lock(g_mock.mutex);
        ASSERT_EQ(g_mock.vendor_id_calls, 0,
                  "malformed durable state must not be replaced from the vendor id");
        ASSERT_EQ(g_mock.secure_set_calls, 0,
                  "malformed durable state must not be silently overwritten");
    }
    clear_adapter();
    return TEST_PASS();
}

TestResult test_malformed_vendor_id_falls_back_to_generated_uuid() {
    prepare(/*with_vendor_id=*/true);
    {
        std::lock_guard<std::mutex> lock(g_mock.mutex);
        g_mock.vendor_id = "vendor-id-with-invalid-format";
    }

    char buf[64] = {0};
    const rac_result_t rc = rac_device_get_or_create_persistent_id(buf, sizeof(buf));
    ASSERT_EQ(rc, RAC_SUCCESS, "malformed optional vendor ids should use a generated UUID");
    const std::string id(buf);
    ASSERT_TRUE(looks_like_uuid(id), std::string("expected canonical UUID, got: ") + id);
    ASSERT_TRUE(id != "vendor-id-with-invalid-format",
                "malformed vendor ids must never become persistent identities");
    {
        std::lock_guard<std::mutex> lock(g_mock.mutex);
        ASSERT_EQ(g_mock.vendor_id_calls, 1, "vendor id should be attempted once");
        ASSERT_EQ(g_mock.secure_set_calls, 1, "generated UUID should be persisted once");
        ASSERT_TRUE(g_mock.stored == id, "secure storage should contain the generated UUID");
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

TestResult test_missing_secure_get_fails_closed() {
    prepare(/*with_vendor_id=*/false);
    g_adapter.secure_get = nullptr;

    char buf[64] = "sentinel";
    rac_result_t rc = rac_device_get_or_create_persistent_id(buf, sizeof(buf));
    ASSERT_EQ(rc, RAC_ERROR_ADAPTER_NOT_SET, "missing secure_get must fail closed");
    ASSERT_TRUE(buf[0] == '\0', "missing secure_get must not return an identity");
    clear_adapter();
    return TEST_PASS();
}

TestResult test_missing_secure_set_fails_closed() {
    prepare(/*with_vendor_id=*/false);
    g_adapter.secure_set = nullptr;

    char buf[64] = "sentinel";
    rac_result_t rc = rac_device_get_or_create_persistent_id(buf, sizeof(buf));
    ASSERT_EQ(rc, RAC_ERROR_ADAPTER_NOT_SET, "missing secure_set must fail closed");
    ASSERT_TRUE(buf[0] == '\0', "missing secure_set must not return an identity");
    clear_adapter();
    return TEST_PASS();
}

}  // namespace

int main(int argc, char** argv) {
    TestSuite suite("device_identity");
    suite.add("secure_get_hit", test_secure_get_hit);
    suite.add("durable_hit_does_not_mask_later_read_failure",
              test_durable_hit_does_not_mask_later_read_failure);
    suite.add("secure_get_miss_vendor_id_present", test_secure_get_miss_vendor_id_present);
    suite.add("secure_get_miss_no_vendor_id_generates_uuid",
              test_secure_get_miss_no_vendor_id_generates_uuid);
    suite.add("vendor_id_write_failure_is_not_returned_or_cached",
              test_vendor_id_write_failure_is_not_returned_or_cached);
    suite.add("generated_uuid_write_failure_is_not_returned_or_cached",
              test_generated_uuid_write_failure_is_not_returned_or_cached);
    suite.add("noncanonical_not_found_fails_closed", test_noncanonical_not_found_fails_closed);
    suite.add("secure_get_success_with_null_value_fails_closed",
              test_secure_get_success_with_null_value_fails_closed);
    suite.add("malformed_stored_id_fails_closed", test_malformed_stored_id_fails_closed);
    suite.add("malformed_vendor_id_falls_back_to_generated_uuid",
              test_malformed_vendor_id_falls_back_to_generated_uuid);
    suite.add("concurrent_calls_return_same_id", test_concurrent_calls_return_same_id);
    suite.add("null_out_rejected", test_null_out_rejected);
    suite.add("buffer_too_small_rejected", test_buffer_too_small_rejected);
    suite.add("missing_secure_get_fails_closed", test_missing_secure_get_fails_closed);
    suite.add("missing_secure_set_fails_closed", test_missing_secure_set_fails_closed);
    return suite.run(argc, argv);
}
