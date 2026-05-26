/**
 * @file vad_threshold_registry.cpp
 * @brief Implementation of the shared per-handle VAD threshold-mutex registry.
 *
 * See `vad_threshold_registry.h` for rationale (commons-features-voice-001 /
 * voice-006).
 */

#include "vad_threshold_registry.h"

#include <memory>
#include <mutex>
#include <unordered_map>

#include "rac/core/rac_types.h"

namespace rac::vad {

namespace {

std::mutex& registry_mutex() {
    static std::mutex m;
    return m;
}

std::unordered_map<rac_handle_t, std::shared_ptr<std::mutex>>& registry() {
    static std::unordered_map<rac_handle_t, std::shared_ptr<std::mutex>> m;
    return m;
}

}  // namespace

std::shared_ptr<std::mutex> get_or_create_threshold_mutex(rac_handle_t handle) {
    std::lock_guard<std::mutex> lock(registry_mutex());
    auto& mutexes = registry();
    auto it = mutexes.find(handle);
    if (it != mutexes.end()) {
        return it->second;
    }
    auto m = std::make_shared<std::mutex>();
    mutexes.emplace(handle, m);
    return m;
}

void erase_threshold_mutex(rac_handle_t handle) {
    std::lock_guard<std::mutex> lock(registry_mutex());
    registry().erase(handle);
}

}  // namespace rac::vad
