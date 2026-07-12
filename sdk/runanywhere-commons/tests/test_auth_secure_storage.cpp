/**
 * @file test_auth_secure_storage.cpp
 * @brief Fail-closed auth persistence and secure-storage status coverage.
 */

#include <cstdio>
#include <cstring>
#include <string>
#include <unordered_map>

#include "rac/core/rac_error.h"
#include "rac/infrastructure/network/rac_auth_manager.h"

namespace {

int test_count = 0;
int fail_count = 0;

#define CHECK(cond, label)                                                                       \
    do {                                                                                         \
        ++test_count;                                                                            \
        if (!(cond)) {                                                                           \
            ++fail_count;                                                                        \
            std::fprintf(stderr, "  FAIL: %s (%s:%d) - %s\n", label, __FILE__, __LINE__, #cond); \
        } else {                                                                                 \
            std::fprintf(stdout, "  ok:   %s\n", label);                                         \
        }                                                                                        \
    } while (0)

struct FakeSecureStorage {
    std::unordered_map<std::string, std::string> values;
    std::string failing_store_key;
    std::string failing_retrieve_key;
    std::string failing_delete_key;
    int delete_calls = 0;
};

int store_value(const char* key, const char* value, void* context) {
    auto* storage = static_cast<FakeSecureStorage*>(context);
    if (key == nullptr || value == nullptr || storage == nullptr) {
        return -1;
    }
    if (storage->failing_store_key == key) {
        return -1;
    }
    storage->values[key] = value;
    return 0;
}

int retrieve_value(const char* key, char* out_value, size_t buffer_size, void* context) {
    auto* storage = static_cast<FakeSecureStorage*>(context);
    if (key == nullptr || out_value == nullptr || buffer_size == 0 || storage == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (storage->failing_retrieve_key == key) {
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }
    const auto found = storage->values.find(key);
    if (found == storage->values.end()) {
        return RAC_ERROR_FILE_NOT_FOUND;
    }
    if (found->second.size() + 1 > buffer_size) {
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }
    std::memcpy(out_value, found->second.c_str(), found->second.size() + 1);
    return static_cast<int>(found->second.size());
}

int delete_value(const char* key, void* context) {
    auto* storage = static_cast<FakeSecureStorage*>(context);
    if (key == nullptr || storage == nullptr) {
        return -1;
    }
    ++storage->delete_calls;
    if (storage->failing_delete_key == key) {
        return -1;
    }
    storage->values.erase(key);
    return 0;
}

rac_secure_storage_t make_storage(FakeSecureStorage* context) {
    rac_secure_storage_t storage = {};
    storage.store = store_value;
    storage.retrieve = retrieve_value;
    storage.delete_key = delete_value;
    storage.context = context;
    return storage;
}

constexpr const char* kAuthResponse =
    R"({"access_token":"access-1","refresh_token":"refresh-1","device_id":"device-1","user_id":"user-1","organization_id":"org-1","token_type":"bearer","expires_in":3600})";
constexpr const char* kAuthResponseWithoutOptionalIdentity =
    R"({"access_token":"access-2","refresh_token":"refresh-2","token_type":"bearer","expires_in":3600})";

}  // namespace

int main() {
    std::fprintf(stdout, "test_auth_secure_storage\n");

    FakeSecureStorage fake;
    rac_secure_storage_t storage = make_storage(&fake);

    rac_auth_init(&storage);
    CHECK(rac_auth_load_stored_tokens() == RAC_ERROR_FILE_NOT_FOUND,
          "clean access-token miss stays distinct");

    fake.failing_retrieve_key = RAC_KEY_ACCESS_TOKEN;
    CHECK(rac_auth_load_stored_tokens() == RAC_ERROR_SECURE_STORAGE_FAILED,
          "authenticated access-token read failure propagates");
    fake.failing_retrieve_key.clear();

    fake.values[RAC_KEY_ACCESS_TOKEN] = "";
    CHECK(rac_auth_load_stored_tokens() == RAC_ERROR_SECURE_STORAGE_FAILED,
          "present empty access token is storage corruption, not a clean miss");

    fake.values[RAC_KEY_ACCESS_TOKEN] = "stored-access";
    fake.values[RAC_KEY_REFRESH_TOKEN] = "";
    CHECK(rac_auth_load_stored_tokens() == RAC_ERROR_SECURE_STORAGE_FAILED,
          "present empty optional token is storage corruption, not omission");
    fake.values.erase(RAC_KEY_REFRESH_TOKEN);
    CHECK(rac_auth_load_stored_tokens() == RAC_SUCCESS,
          "optional clean misses do not block token restore");
    CHECK(rac_auth_is_authenticated(), "successful restore authenticates state");
    CHECK(std::strcmp(rac_auth_get_access_token(), "stored-access") == 0,
          "successful restore retains exact access token");

    rac_auth_init(&storage);
    fake.values.clear();
    fake.failing_store_key = RAC_KEY_REFRESH_TOKEN;
    fake.delete_calls = 0;
    CHECK(rac_auth_handle_authenticate_response(kAuthResponse) == RAC_ERROR_SECURE_STORAGE_FAILED,
          "authentication reports durable persistence failure");
    CHECK(!rac_auth_is_authenticated(), "persistence failure clears in-memory auth state");
    CHECK(fake.delete_calls == 5, "persistence rollback attempts every auth-key deletion");
    CHECK(fake.values.empty(), "persistence rollback removes partial durable state");

    fake.failing_store_key.clear();
    fake.failing_delete_key.clear();
    fake.delete_calls = 0;
    CHECK(rac_auth_handle_authenticate_response(kAuthResponse) == RAC_SUCCESS,
          "authentication succeeds when every secure write commits");
    fake.delete_calls = 0;
    CHECK(rac_auth_handle_refresh_response(kAuthResponseWithoutOptionalIdentity) == RAC_SUCCESS,
          "refresh succeeds when optional identity is omitted");
    CHECK(fake.delete_calls == 3, "refresh deletes every omitted optional identity value");
    CHECK(fake.values.size() == 2 && fake.values.count(RAC_KEY_ACCESS_TOKEN) == 1 &&
              fake.values.count(RAC_KEY_REFRESH_TOKEN) == 1,
          "durable auth snapshot contains no stale optional identity");

    fake.failing_delete_key = RAC_KEY_REFRESH_TOKEN;
    fake.delete_calls = 0;
    CHECK(rac_auth_clear() == RAC_ERROR_SECURE_STORAGE_FAILED,
          "logout reports a durable deletion failure");
    CHECK(fake.delete_calls == 5, "logout attempts every deletion after one fails");
    CHECK(!rac_auth_is_authenticated(), "logout always clears process-local auth state");
    CHECK(fake.values.size() == 1 && fake.values.count(RAC_KEY_REFRESH_TOKEN) == 1,
          "only the injected failed deletion remains persisted");

    fake.failing_delete_key.clear();
    CHECK(rac_auth_clear() == RAC_SUCCESS, "logout succeeds after durable storage recovers");
    CHECK(fake.values.empty(), "successful logout removes all persisted auth state");

    std::fprintf(stdout, "  %d checks, %d failures\n", test_count, fail_count);
    return fail_count == 0 ? 0 : 1;
}
