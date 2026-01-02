/**
 * @file event_publisher.cpp
 * @brief RunAnywhere Commons - Event Publisher Implementation
 *
 * C++ port of Swift's EventPublisher.swift
 * Provides category-based event subscription matching Swift's pattern.
 */

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/events/rac_events.h"

// =============================================================================
// INTERNAL STORAGE
// =============================================================================

namespace {

struct Subscription {
    uint64_t id;
    rac_event_callback_fn callback;
    void* user_data;
};

std::mutex g_event_mutex;
std::atomic<uint64_t> g_next_subscription_id{1};

// Subscriptions per category
std::unordered_map<rac_event_category_t, std::vector<Subscription>> g_subscriptions;

// All-events subscriptions
std::vector<Subscription> g_all_subscriptions;

// Sentinel category for "all events"
const rac_event_category_t CATEGORY_ALL_SENTINEL = static_cast<rac_event_category_t>(-1);

uint64_t current_time_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

// Generate a simple UUID-like ID
std::string generate_event_id() {
    static std::atomic<uint64_t> counter{0};
    auto now = current_time_ms();
    auto count = counter.fetch_add(1);
    char buffer[64];
    snprintf(buffer, sizeof(buffer), "%llu-%llu", static_cast<unsigned long long>(now),
             static_cast<unsigned long long>(count));
    return buffer;
}

}  // namespace

// =============================================================================
// EVENT SUBSCRIPTION API
// =============================================================================

extern "C" {

uint64_t rac_event_subscribe(rac_event_category_t category, rac_event_callback_fn callback,
                             void* user_data) {
    if (callback == nullptr) {
        return 0;
    }

    std::lock_guard<std::mutex> lock(g_event_mutex);

    Subscription sub;
    sub.id = g_next_subscription_id.fetch_add(1);
    sub.callback = callback;
    sub.user_data = user_data;

    g_subscriptions[category].push_back(sub);

    return sub.id;
}

uint64_t rac_event_subscribe_all(rac_event_callback_fn callback, void* user_data) {
    if (callback == nullptr) {
        return 0;
    }

    std::lock_guard<std::mutex> lock(g_event_mutex);

    Subscription sub;
    sub.id = g_next_subscription_id.fetch_add(1);
    sub.callback = callback;
    sub.user_data = user_data;

    g_all_subscriptions.push_back(sub);

    return sub.id;
}

void rac_event_unsubscribe(uint64_t subscription_id) {
    if (subscription_id == 0) {
        return;
    }

    std::lock_guard<std::mutex> lock(g_event_mutex);

    auto remove_from = [subscription_id](std::vector<Subscription>& subs) {
        auto it =
            std::remove_if(subs.begin(), subs.end(), [subscription_id](const Subscription& s) {
                return s.id == subscription_id;
            });
        if (it != subs.end()) {
            subs.erase(it, subs.end());
            return true;
        }
        return false;
    };

    // Check all-events subscriptions
    if (remove_from(g_all_subscriptions)) {
        return;
    }

    // Check category-specific subscriptions
    for (auto& pair : g_subscriptions) {
        if (remove_from(pair.second)) {
            return;
        }
    }
}

rac_result_t rac_event_publish(const rac_event_t* event) {
    if (event == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    // Create a copy with timestamp if not set
    rac_event_t event_copy = *event;
    if (event_copy.timestamp_ms == 0) {
        event_copy.timestamp_ms = static_cast<int64_t>(current_time_ms());
    }

    std::lock_guard<std::mutex> lock(g_event_mutex);

    // Notify category-specific subscribers
    auto it = g_subscriptions.find(event_copy.category);
    if (it != g_subscriptions.end()) {
        for (const auto& sub : it->second) {
            sub.callback(&event_copy, sub.user_data);
        }
    }

    // Notify all-events subscribers
    for (const auto& sub : g_all_subscriptions) {
        sub.callback(&event_copy, sub.user_data);
    }

    return RAC_SUCCESS;
}

rac_result_t rac_event_track(const char* type, rac_event_category_t category,
                             rac_event_destination_t destination, const char* properties_json) {
    if (type == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    // Generate event ID
    static thread_local std::string s_event_id;
    s_event_id = generate_event_id();

    rac_event_t event = {};
    event.id = s_event_id.c_str();
    event.type = type;
    event.category = category;
    event.timestamp_ms = static_cast<int64_t>(current_time_ms());
    event.session_id = nullptr;
    event.destination = destination;
    event.properties_json = properties_json;

    return rac_event_publish(&event);
}

const char* rac_event_category_name(rac_event_category_t category) {
    switch (category) {
        case RAC_EVENT_CATEGORY_SDK:
            return "sdk";
        case RAC_EVENT_CATEGORY_MODEL:
            return "model";
        case RAC_EVENT_CATEGORY_LLM:
            return "llm";
        case RAC_EVENT_CATEGORY_STT:
            return "stt";
        case RAC_EVENT_CATEGORY_TTS:
            return "tts";
        case RAC_EVENT_CATEGORY_VOICE:
            return "voice";
        case RAC_EVENT_CATEGORY_STORAGE:
            return "storage";
        case RAC_EVENT_CATEGORY_DEVICE:
            return "device";
        case RAC_EVENT_CATEGORY_NETWORK:
            return "network";
        case RAC_EVENT_CATEGORY_ERROR:
            return "error";
        default:
            return "unknown";
    }
}

}  // extern "C"

// =============================================================================
// INTERNAL RESET (for testing)
// =============================================================================

namespace rac_internal {

void reset_event_publisher() {
    std::lock_guard<std::mutex> lock(g_event_mutex);
    g_subscriptions.clear();
    g_all_subscriptions.clear();
    g_next_subscription_id.store(1);
}

}  // namespace rac_internal
