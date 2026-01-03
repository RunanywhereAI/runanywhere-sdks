/**
 * @file EventBridge.cpp
 * @brief Event bridge implementation
 */

#include "EventBridge.hpp"

namespace runanywhere {
namespace bridges {

EventBridge& EventBridge::shared() {
    static EventBridge instance;
    return instance;
}

EventBridge::~EventBridge() {
    shutdown();
}

void EventBridge::initialize(EventCallback callback) {
    if (initialized_) {
        return;
    }

    callback_ = callback;

#ifdef HAS_RACOMMONS
    // Subscribe to all events from commons
    rac_event_subscribe(onEvent, this);
#endif

    initialized_ = true;
}

void EventBridge::shutdown() {
    if (!initialized_) {
        return;
    }

#ifdef HAS_RACOMMONS
    rac_event_unsubscribe(onEvent);
#endif

    callback_ = nullptr;
    initialized_ = false;
}

void EventBridge::emit(const std::string& eventJson) {
    if (callback_) {
        callback_(eventJson);
    }
}

#ifdef HAS_RACOMMONS
void EventBridge::onEvent(const char* event_json, void* user_data) {
    auto* bridge = static_cast<EventBridge*>(user_data);
    if (bridge && bridge->callback_ && event_json) {
        bridge->callback_(event_json);
    }
}
#endif

} // namespace bridges
} // namespace runanywhere
