/**
 * HybridRunAnywhereCore+SecureStorage.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 */
#include "HybridRunAnywhereCore+Common.hpp"

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

// Secure Storage
// ============================================================================
// Secure Storage Methods
// Matches Swift: KeychainManager.swift
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::secureStorageSet(
    const std::string& key,
    const std::string& value) {
    return Promise<bool>::async([key, value]() -> bool {
        LOGI("Secure storage set: key=%s", key.c_str());

        bool success = InitBridge::shared().secureSet(key, value);
        if (!success) {
            LOGE("Failed to store value for key: %s", key.c_str());
        }
        return success;
    });
}

std::shared_ptr<Promise<std::variant<nitro::NullType, std::string>>> HybridRunAnywhereCore::secureStorageGet(
    const std::string& key) {
    return Promise<std::variant<nitro::NullType, std::string>>::async([key]() -> std::variant<nitro::NullType, std::string> {
        LOGI("Secure storage get: key=%s", key.c_str());

        std::string value;
        if (InitBridge::shared().secureGet(key, value)) {
            return value;
        }
        return nitro::NullType();
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::secureStorageDelete(
    const std::string& key) {
    return Promise<bool>::async([key]() -> bool {
        LOGI("Secure storage delete: key=%s", key.c_str());

        bool success = InitBridge::shared().secureDelete(key);
        if (!success) {
            LOGE("Failed to delete key: %s", key.c_str());
        }
        return success;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::secureStorageExists(
    const std::string& key) {
    return Promise<bool>::async([key]() -> bool {
        LOGD("Secure storage exists: key=%s", key.c_str());
        return InitBridge::shared().secureExists(key);
    });
}

// Semantic aliases for set/get (forward to actual implementations)
std::shared_ptr<Promise<void>> HybridRunAnywhereCore::secureStorageStore(
    const std::string& key,
    const std::string& value) {
    // Direct implementation (no double-wrapping of promises)
    return Promise<void>::async([key, value]() -> void {
        LOGI("Secure storage store: key=%s", key.c_str());
        bool success = InitBridge::shared().secureSet(key, value);
        if (!success) {
            LOGE("Failed to store value for key: %s", key.c_str());
            throw std::runtime_error("Failed to store value for key: " + key);
        }
    });
}

std::shared_ptr<Promise<std::variant<nitro::NullType, std::string>>> HybridRunAnywhereCore::secureStorageRetrieve(
    const std::string& key) {
    // Direct implementation (reuse exact same logic as secureStorageGet)
    return Promise<std::variant<nitro::NullType, std::string>>::async([key]() -> std::variant<nitro::NullType, std::string> {
        LOGI("Secure storage retrieve: key=%s", key.c_str());
        std::string value;
        if (InitBridge::shared().secureGet(key, value)) {
            return value;
        }
        return nitro::NullType();
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getPersistentDeviceUUID() {
    return Promise<std::string>::async([]() -> std::string {
        LOGI("Getting persistent device UUID...");

        std::string uuid = InitBridge::shared().getPersistentDeviceUUID();

        if (uuid.empty()) {
            throw std::runtime_error("Failed to get or generate device UUID");
        }

        LOGI("Persistent device UUID: %s", uuid.c_str());
        return uuid;
    });
}

} // namespace margelo::nitro::runanywhere
