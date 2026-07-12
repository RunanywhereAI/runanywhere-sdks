/**
 * HybridRunAnywhereCore+SecureStorage.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 */
#include "HybridRunAnywhereCore+Common.hpp"

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

// ============================================================================
// Device Identity
// ============================================================================

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getPersistentDeviceUUID() {
    return Promise<std::string>::async([]() -> std::string {
        LOGD("Getting persistent device UUID...");

        std::string uuid;
        rac_result_t result =
            InitBridge::shared().getPersistentDeviceUUID(uuid);
        if (result != RAC_SUCCESS) {
          throw std::runtime_error(
              "RAC_RESULT=" + std::to_string(static_cast<int>(result)) +
              " persistent_device_id");
        }

        return uuid;
    });
}

} // namespace margelo::nitro::runanywhere
