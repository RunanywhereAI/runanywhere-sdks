/**
 * @file EventBridge.cpp
 * @brief C++ bridge for event operations.
 *
 * Simplified event bridge that manages event callbacks locally.
 * Does not depend on RACommons event functions (which may not be exported).
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
    LOGI("Event callback registered");
}

void EventBridge::registerForEvents() {
    if (isRegistered_) {
        LOGD("Already registered for events");
        return;
    }

    isRegistered_ = true;
    LOGI("Event registration enabled");
}

void EventBridge::unregisterFromEvents() {
    if (!isRegistered_) {
        return;
    }

    isRegistered_ = false;
    LOGI("Event registration disabled");
}

rac_result_t EventBridge::trackEvent(
    const std::string& type,
    EventCategory category,
    EventDestination destination,
    const std::string& propertiesJson
) {
    LOGD("trackEvent: type=%s category=%d", type.c_str(), static_cast<int>(category));

    // If we have a callback registered, forward the event
    if (eventCallback_) {
        SDKEvent event;
        auto now = std::chrono::system_clock::now();
        auto millis = std::chrono::duration_cast<std::chrono::milliseconds>(
            now.time_since_epoch()).count();

        event.id = std::to_string(millis);
        event.type = type;
        event.category = category;
        event.timestampMs = millis;
        event.destination = destination;
        event.propertiesJson = propertiesJson;

        eventCallback_(event);
    }

    return RAC_SUCCESS;
}

rac_result_t EventBridge::publishEvent(const SDKEvent& event) {
    LOGD("publishEvent: type=%s", event.type.c_str());

    // If we have a callback registered, forward the event
    if (eventCallback_) {
        eventCallback_(event);
    }

    return RAC_SUCCESS;
}

std::string EventBridge::getCategoryName(EventCategory category) {
    switch (category) {
        case EventCategory::SDK: return "sdk";
        case EventCategory::Model: return "model";
        case EventCategory::LLM: return "llm";
        case EventCategory::STT: return "stt";
        case EventCategory::TTS: return "tts";
        case EventCategory::Voice: return "voice";
        case EventCategory::Storage: return "storage";
        case EventCategory::Device: return "device";
        case EventCategory::Network: return "network";
        case EventCategory::Error: return "error";
        case EventCategory::Analytics: return "analytics";
        case EventCategory::Performance: return "performance";
        case EventCategory::User: return "user";
        default: return "unknown";
    }
}

} // namespace bridges
} // namespace runanywhere
