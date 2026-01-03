/**
 * @file InitBridge.cpp
 * @brief SDK initialization bridge implementation
 */

#include "InitBridge.hpp"

namespace runanywhere {
namespace bridges {

InitBridge& InitBridge::shared() {
    static InitBridge instance;
    return instance;
}

InitBridge::~InitBridge() {
    shutdown();
}

rac_result_t InitBridge::initialize(const std::string& configJson) {
    if (initialized_) {
        return RAC_SUCCESS;
    }

#ifdef HAS_RACOMMONS
    // Parse config and initialize
    // TODO: Parse configJson and pass to rac_init
    rac_result_t result = rac_init();
    if (result != RAC_SUCCESS) {
        return result;
    }
#endif

    initialized_ = true;
    return RAC_SUCCESS;
}

void InitBridge::shutdown() {
    if (!initialized_) {
        return;
    }

#ifdef HAS_RACOMMONS
    rac_shutdown();
#endif

    initialized_ = false;
}

} // namespace bridges
} // namespace runanywhere
