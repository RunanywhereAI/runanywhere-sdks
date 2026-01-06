/**
 * @file EventBridge.hpp
 * @brief C++ bridge for event operations.
 *
 * Mirrors Swift's event handling pattern:
 * - Subscribe to events via rac_event_subscribe()
 * - Forward events to JS layer
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Events/
 */

#pragma once

#include <string>
#include <functional>
#include <vector>
#include <cstdint>

#include "rac/core/rac_types.h"
#include "rac/infrastructure/events/rac_events.h"

namespace runanywhere {
namespace bridges {

/**
 * Event category enum matching RAC
 */
enum class EventCategory {
    SDK = 0,
    Model = 1,
    LLM = 2,
    STT = 3,
    TTS = 4,
    Voice = 5,
    Storage = 6,
    Device = 7,
    Network = 8,
    Error = 9
};

/**
 * Event destination enum matching RAC
 */
enum class EventDestination {
    PublicOnly = 0,
    AnalyticsOnly = 1,
    All = 2
};

/**
 * Event data structure
 */
struct SDKEvent {
    std::string id;
    std::string type;
    EventCategory category = EventCategory::SDK;
    int64_t timestampMs = 0;
    std::string sessionId;
    EventDestination destination = EventDestination::All;
    std::string propertiesJson;
};

/**
 * Event callback type
 */
using EventCallback = std::function<void(const SDKEvent&)>;

/**
 * EventBridge - Event subscription and publishing
 *
 * Mirrors Swift's EventBridge pattern:
 * - Subscribe to C++ events
 * - Forward to JS layer
 * - Track events via rac_event_track()
 */
class EventBridge {
public:
    /**
     * Get shared instance
     */
    static EventBridge& shared();

    /**
     * Register event callback for JS layer
     * Events will be forwarded to this callback
     */
    void setEventCallback(EventCallback callback);

    /**
     * Register with RACommons to receive events
     * Must be called during SDK initialization
     */
    void registerForEvents();

    /**
     * Unregister from RACommons events
     */
    void unregisterFromEvents();

    /**
     * Track an event
     *
     * @param type Event type string
     * @param category Event category
     * @param destination Where to route this event
     * @param propertiesJson Event properties as JSON
     */
    rac_result_t trackEvent(
        const std::string& type,
        EventCategory category,
        EventDestination destination,
        const std::string& propertiesJson
    );

    /**
     * Publish an event
     */
    rac_result_t publishEvent(const SDKEvent& event);

    /**
     * Get category name
     */
    static std::string getCategoryName(EventCategory category);

private:
    EventBridge() = default;
    ~EventBridge();
    EventBridge(const EventBridge&) = delete;
    EventBridge& operator=(const EventBridge&) = delete;

    EventCallback eventCallback_;
    uint64_t subscriptionId_ = 0;
    bool isRegistered_ = false;
};

} // namespace bridges
} // namespace runanywhere
