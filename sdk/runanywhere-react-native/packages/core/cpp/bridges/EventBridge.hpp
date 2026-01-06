/**
 * @file EventBridge.hpp
 * @brief Event bridge for React Native
 *
 * Routes native events from runanywhere-commons to JavaScript/React Native.
 * Matches Swift's CppBridge+Events.swift pattern.
 */

#pragma once

#include <functional>
#include <memory>
#include <string>

#ifdef HAS_RACOMMONS
#include "rac/infrastructure/events/rac_events.h"
#endif

namespace runanywhere {
namespace bridges {

/**
 * @brief Event callback type
 */
using EventCallback = std::function<void(const std::string& eventJson)>;

/**
 * @brief Event bridge singleton
 *
 * Routes events from commons to React Native.
 */
class EventBridge {
public:
    static EventBridge& shared();

    /**
     * @brief Initialize with JavaScript callback
     *
     * @param callback Function to call when events are received
     */
    void initialize(EventCallback callback);

    /**
     * @brief Shutdown event bridge
     */
    void shutdown();

    /**
     * @brief Emit an event to JavaScript
     *
     * @param eventJson JSON-encoded event
     */
    void emit(const std::string& eventJson);

private:
    EventBridge() = default;
    ~EventBridge();

    // Disable copy/move
    EventBridge(const EventBridge&) = delete;
    EventBridge& operator=(const EventBridge&) = delete;

    EventCallback callback_;
    bool initialized_ = false;

#ifdef HAS_RACOMMONS
    static void onEvent(const char* event_json, void* user_data);
#endif
};

} // namespace bridges
} // namespace runanywhere
