/**
 * @file EventBridge.cpp
 * @brief C++ bridge for event operations.
 *
 * Mirrors Swift's event handling pattern.
 */

#include "EventBridge.hpp"
#include <chrono>

// Platform-specific logging
#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "EventBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#include <cstdio>
#define LOGI(...) printf("[EventBridge] "); printf(__VA_ARGS__); printf("\n")
#define LOGD(...) printf("[EventBridge DEBUG] "); printf(__VA_ARGS__); printf("\n")
#define LOGE(...) printf("[EventBridge ERROR] "); printf(__VA_ARGS__); printf("\n")
#endif

namespace runanywhere {
namespace bridges {

// =============================================================================
// Static storage for callback (needed for C function pointer)
// =============================================================================

static EventCallback* g_eventCallback = nullptr;

// =============================================================================
// C Callback Implementation (called by RACommons)
// =============================================================================

static void eventCallbackHandler(const rac_event_t* event, void* userData) {
    if (!event || !g_eventCallback || !(*g_eventCallback)) {
        return;
    }

    SDKEvent sdkEvent;
    sdkEvent.id = event->id ? event->id : "";
    sdkEvent.type = event->type ? event->type : "";
    sdkEvent.category = static_cast<EventCategory>(event->category);
    sdkEvent.timestampMs = event->timestamp_ms;
    sdkEvent.sessionId = event->session_id ? event->session_id : "";
    sdkEvent.destination = static_cast<EventDestination>(event->destination);
    sdkEvent.propertiesJson = event->properties_json ? event->properties_json : "";

    // Invoke the callback
    (*g_eventCallback)(sdkEvent);
}

// =============================================================================
// EventBridge Implementation
// =============================================================================

EventBridge& EventBridge::shared() {
    static EventBridge instance;
    return instance;
}

EventBridge::~EventBridge() {
    unregisterFromEvents();
}

void EventBridge::setEventCallback(EventCallback callback) {
    eventCallback_ = callback;

    // Store in global for C callback
    static EventCallback storedCallback;
    storedCallback = callback;
    g_eventCallback = &storedCallback;

    LOGI("Event callback registered");
}

void EventBridge::registerForEvents() {
    if (isRegistered_) {
        LOGD("Already registered for events");
        return;
    }

    // Subscribe to all events
    subscriptionId_ = rac_event_subscribe_all(eventCallbackHandler, nullptr);

    if (subscriptionId_ != 0) {
        isRegistered_ = true;
        LOGI("Registered for all events (subscription ID: %llu)",
             static_cast<unsigned long long>(subscriptionId_));
    } else {
        LOGE("Failed to subscribe to events");
    }
}

void EventBridge::unregisterFromEvents() {
    if (!isRegistered_ || subscriptionId_ == 0) {
        return;
    }

    rac_event_unsubscribe(subscriptionId_);
    subscriptionId_ = 0;
    isRegistered_ = false;

    LOGI("Unregistered from events");
}

rac_result_t EventBridge::trackEvent(
    const std::string& type,
    EventCategory category,
    EventDestination destination,
    const std::string& propertiesJson
) {
    rac_result_t result = rac_event_track(
        type.c_str(),
        static_cast<rac_event_category_t>(category),
        static_cast<rac_event_destination_t>(destination),
        propertiesJson.empty() ? nullptr : propertiesJson.c_str()
    );

    if (result != RAC_SUCCESS) {
        LOGE("Failed to track event %s: %d", type.c_str(), result);
    }

    return result;
}

rac_result_t EventBridge::publishEvent(const SDKEvent& event) {
    rac_event_t racEvent = {};
    racEvent.id = event.id.c_str();
    racEvent.type = event.type.c_str();
    racEvent.category = static_cast<rac_event_category_t>(event.category);
    racEvent.timestamp_ms = event.timestampMs;
    racEvent.session_id = event.sessionId.empty() ? nullptr : event.sessionId.c_str();
    racEvent.destination = static_cast<rac_event_destination_t>(event.destination);
    racEvent.properties_json = event.propertiesJson.empty() ? nullptr : event.propertiesJson.c_str();

    rac_result_t result = rac_event_publish(&racEvent);

    if (result != RAC_SUCCESS) {
        LOGE("Failed to publish event %s: %d", event.type.c_str(), result);
    }

    return result;
}

std::string EventBridge::getCategoryName(EventCategory category) {
    const char* name = rac_event_category_name(static_cast<rac_event_category_t>(category));
    return name ? name : "unknown";
}

} // namespace bridges
} // namespace runanywhere
