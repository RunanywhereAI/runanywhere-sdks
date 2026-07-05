/**
 * HybridRunAnywhereCore+SecureStorage.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 */
#include "HybridRunAnywhereCore+Common.hpp"

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

// Device Identity

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getPersistentDeviceUUID() {
    return Promise<std::string>::async([]() -> std::string {
        LOGD("Getting persistent device UUID...");

        std::string uuid = InitBridge::shared().getPersistentDeviceUUID();

        if (uuid.empty()) {
            throw std::runtime_error("Failed to get or generate device UUID");
        }

        // Device UUID is a persistent identity correlator (PII). logcat / Console.app
        // are collected by QA tooling, crash reporters, MDM agents, and adb sessions,
        // so never log the full value at INFO. Redact to first 4 / last 4 hex chars.
        if (uuid.size() >= 8) {
            LOGD("Persistent device UUID: %.4s...%.4s", uuid.c_str(), uuid.c_str() + uuid.size() - 4);
        } else {
            LOGD("Persistent device UUID: <redacted, %zu chars>", uuid.size());
        }
        return uuid;
    });
}

} // namespace margelo::nitro::runanywhere
