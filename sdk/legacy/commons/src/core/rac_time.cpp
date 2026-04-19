/**
 * @file rac_time.cpp
 * @brief RunAnywhere Commons - Time Utilities
 */

#include <chrono>

#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_types.h"

extern "C" {

int64_t rac_get_current_time_ms(void) {
    // First try platform adapter if available
    const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
    if (adapter != nullptr && adapter->now_ms != nullptr) {
        return adapter->now_ms(adapter->user_data);
    }

    // Fallback to system clock
    auto now = std::chrono::system_clock::now();
    auto duration = now.time_since_epoch();
    return std::chrono::duration_cast<std::chrono::milliseconds>(duration).count();
}

}  // extern "C"
