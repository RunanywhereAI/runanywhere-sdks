/**
 * @file device_identity.cpp
 * @brief Implementation of rac_device_get_or_create_persistent_id (P2-T13).
 *
 * Centralizes the device-UUID resolution chain that Swift / Kotlin / RN /
 * Flutter / Web each used to reimplement:
 *
 *   secure_get("com.runanywhere.sdk.device.uuid") -> get_vendor_id (if available)
 *       -> generate UUID
 *
 * On cache miss the resolved value is persisted back through secure_set so
 * the next process can short-circuit on the cache hit.
 */

#include <cstring>
#include <mutex>
#include <random>
#include <sstream>
#include <string>

#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/device/rac_device_identity.h"

namespace {

constexpr const char* kLogCategory = "DeviceIdentity";
constexpr const char* kSecureStorageKey = "com.runanywhere.sdk.device.uuid";
constexpr size_t kCanonicalUuidLen = 36u;  // 8-4-4-4-12 plus four hyphens

struct DeviceIdentityState {
    std::mutex mutex;
    std::string cached;  // empty when uncached
    const rac_platform_adapter_t* cached_adapter = nullptr;
};

DeviceIdentityState& get_state() {
    static DeviceIdentityState state;
    return state;
}

/**
 * Generate a canonical RFC-4122 v4 UUID string.
 * Format: 8-4-4-4-12 hex digits with hyphens, version nibble = 4, variant = 10xx.
 * Mirrors the helper Swift/iOS callers historically used.
 */
std::string generate_uuid_v4() {
    static thread_local std::mt19937 gen(std::random_device{}());
    static thread_local std::uniform_int_distribution<int> dis(0, 15);

    std::stringstream ss;
    ss << std::hex;

    for (int i = 0; i < 8; ++i)
        ss << dis(gen);
    ss << '-';
    for (int i = 0; i < 4; ++i)
        ss << dis(gen);
    ss << "-4";  // version 4
    for (int i = 0; i < 3; ++i)
        ss << dis(gen);
    ss << '-';
    ss << (8 + dis(gen) % 4);  // variant: 10xx -> hex digit 8/9/a/b
    for (int i = 0; i < 3; ++i)
        ss << dis(gen);
    ss << '-';
    for (int i = 0; i < 12; ++i)
        ss << dis(gen);

    return ss.str();
}

/**
 * Try to fetch the cached id from secure storage. Returns empty string on
 * cache miss (any error from the adapter is treated as miss; callers fall
 * through to the next branch).
 */
std::string try_secure_get(const rac_platform_adapter_t* adapter) {
    if (!adapter || !adapter->secure_get) {
        return std::string();
    }

    char* raw = nullptr;
    rac_result_t rc = adapter->secure_get(kSecureStorageKey, &raw, adapter->user_data);
    if (rc != RAC_SUCCESS || raw == nullptr) {
        return std::string();
    }

    std::string value(raw);
    rac_free(raw);
    return value;
}

/**
 * Try to fetch the platform vendor ID into a stack buffer. Returns empty
 * string if the callback is unavailable or fails for any reason.
 */
std::string try_vendor_id(const rac_platform_adapter_t* adapter) {
    if (!adapter || !adapter->get_vendor_id) {
        return std::string();
    }

    char buffer[RAC_DEVICE_ID_BUFFER_MIN_SIZE] = {0};
    rac_result_t rc = adapter->get_vendor_id(buffer, sizeof(buffer), adapter->user_data);
    if (rc != RAC_SUCCESS) {
        return std::string();
    }

    // Defensive NUL-termination: callbacks are expected to NUL-terminate but
    // the buffer is stack-local so worst case we truncate to a 36-char UUID.
    buffer[sizeof(buffer) - 1] = '\0';
    if (buffer[0] == '\0') {
        return std::string();
    }
    return std::string(buffer);
}

/**
 * Persist the resolved id back into secure storage. Logs but does not fail
 * the resolution if the write fails — Swift's DeviceIdentity uses `try?` here
 * for the same reason.
 */
void try_secure_set(const rac_platform_adapter_t* adapter, const std::string& value) {
    if (!adapter || !adapter->secure_set) {
        return;
    }
    rac_result_t rc = adapter->secure_set(kSecureStorageKey, value.c_str(), adapter->user_data);
    if (rc != RAC_SUCCESS) {
        RAC_LOG_WARNING(kLogCategory, "Failed to persist device id to secure storage (rc=%d)",
                        static_cast<int>(rc));
    }
}

/**
 * Copy the resolved id into the caller-provided buffer. The caller has
 * already validated buffer/size, so this only checks the "string fits"
 * invariant which is technically guaranteed by the chain (UUID = 36 chars,
 * minimum buffer = 37) but kept defensive against pathological vendor IDs.
 */
rac_result_t copy_into_out(const std::string& value, char* out, size_t out_size) {
    if (value.size() + 1u > out_size) {
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }
    std::memcpy(out, value.data(), value.size());
    out[value.size()] = '\0';
    return RAC_SUCCESS;
}

}  // namespace

extern "C" {

rac_result_t rac_device_get_or_create_persistent_id(char* out, size_t out_size) {
    if (out == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (out_size < RAC_DEVICE_ID_BUFFER_MIN_SIZE) {
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }

    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
    if (adapter == nullptr) {
        RAC_LOG_ERROR(kLogCategory, "Platform adapter not registered");
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    // Re-read secure storage before trusting the in-process cache so a
    // shutdown/re-init with a different backing store cannot return a stale id.
    std::string resolved = try_secure_get(adapter);
    if (!resolved.empty()) {
        RAC_LOG_DEBUG(kLogCategory, "Loaded device id from secure storage");
        state.cached = std::move(resolved);
        state.cached_adapter = adapter;
        return copy_into_out(state.cached, out, out_size);
    }

    if (!state.cached.empty() && state.cached_adapter == adapter && adapter->secure_get == nullptr) {
        return copy_into_out(state.cached, out, out_size);
    }
    state.cached.clear();
    state.cached_adapter = nullptr;

    // 1) Platform vendor id (Apple identifierForVendor, etc.).
    resolved = try_vendor_id(adapter);
    if (!resolved.empty()) {
        RAC_LOG_DEBUG(kLogCategory, "Resolved device id from platform vendor id");
        try_secure_set(adapter, resolved);
        state.cached = std::move(resolved);
        state.cached_adapter = adapter;
        return copy_into_out(state.cached, out, out_size);
    }

    // 2) Synthesize a fresh UUID.
    resolved = generate_uuid_v4();
    if (resolved.size() != kCanonicalUuidLen) {
        // generate_uuid_v4 has a deterministic length contract; this branch is
        // a defensive guard only.
        RAC_LOG_ERROR(kLogCategory, "Generated UUID has unexpected length: %zu", resolved.size());
        return RAC_ERROR_INTERNAL;
    }
    RAC_LOG_DEBUG(kLogCategory, "Generated and persisted new device id");
    try_secure_set(adapter, resolved);
    state.cached = std::move(resolved);
    state.cached_adapter = adapter;
    return copy_into_out(state.cached, out, out_size);
}

void rac_device_identity_reset_cache_for_testing(void) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);
    state.cached.clear();
    state.cached_adapter = nullptr;
}

}  // extern "C"
