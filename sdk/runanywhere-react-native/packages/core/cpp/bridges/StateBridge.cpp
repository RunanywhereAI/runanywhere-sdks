/**
 * @file StateBridge.cpp
 * @brief SDK state bridge implementation
 */

#include "StateBridge.hpp"

namespace runanywhere {
namespace bridges {

StateBridge& StateBridge::shared() {
    static StateBridge instance;
    return instance;
}

bool StateBridge::isSDKInitialized() const {
    return state_ == SDKState::Initialized || state_ == SDKState::ServicesReady;
}

bool StateBridge::areServicesReady() const {
    return state_ == SDKState::ServicesReady;
}

SDKState StateBridge::getState() const {
    return state_;
}

void StateBridge::setState(SDKState state) {
    state_ = state;
}

} // namespace bridges
} // namespace runanywhere
