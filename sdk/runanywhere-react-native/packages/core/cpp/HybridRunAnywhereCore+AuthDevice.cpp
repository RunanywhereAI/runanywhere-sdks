/**
 * HybridRunAnywhereCore+AuthDevice.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 */
#include "HybridRunAnywhereCore+Common.hpp"

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

// Authentication and Device Registration
// ============================================================================
// Authentication
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isAuthenticated() {
    return Promise<bool>::async([]() -> bool {
        return AuthBridge::shared().isAuthenticated();
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getUserId() {
    return Promise<std::string>::async([]() -> std::string {
        return AuthBridge::shared().getUserId();
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getOrganizationId() {
    return Promise<std::string>::async([]() -> std::string {
        return AuthBridge::shared().getOrganizationId();
    });
}

// ============================================================================
// Device Registration
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isDeviceRegistered() {
    return Promise<bool>::async([]() -> bool {
        return DeviceBridge::shared().isRegistered();
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getDeviceId() {
    return Promise<std::string>::async([]() -> std::string {
        return DeviceBridge::shared().getDeviceId();
    });
}

} // namespace margelo::nitro::runanywhere
