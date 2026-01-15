/**
 * @file rac_events.h
 * @brief RunAnywhere Commons - Event Publishing and Subscription
 *
 * C port of Swift's SDKEvent protocol and EventPublisher from:
 * Sources/RunAnywhere/Infrastructure/Events/SDKEvent.swift
 * Sources/RunAnywhere/Infrastructure/Events/EventPublisher.swift
 *
 * Events are categorized and can be routed to different destinations
 * (public EventBus or analytics).
 */

#ifndef RAC_EVENTS_H
#define RAC_EVENTS_H

#include <RACommons/rac_types.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// EVENT DESTINATION - Mirrors Swift's EventDestination
// =============================================================================

/**
 * Where an event should be routed.
 * Mirrors Swift's EventDestination enum.
 */
typedef enum rac_event_destination {
    /** Only to public EventBus (app developers) */
    RAC_EVENT_DESTINATION_PUBLIC_ONLY = 0,
    /** Only to analytics/telemetry (backend) */
    RAC_EVENT_DESTINATION_ANALYTICS_ONLY = 1,
    /** Both destinations (default) */
    RAC_EVENT_DESTINATION_ALL = 2,
} rac_event_destination_t;

// =============================================================================
// EVENT CATEGORY - Mirrors Swift's EventCategory
// =============================================================================

/**
 * Event categories for filtering/grouping.
 * Mirrors Swift's EventCategory enum.
 */
typedef enum rac_event_category {
    RAC_EVENT_CATEGORY_SDK = 0,
    RAC_EVENT_CATEGORY_MODEL = 1,
    RAC_EVENT_CATEGORY_LLM = 2,
    RAC_EVENT_CATEGORY_STT = 3,
    RAC_EVENT_CATEGORY_TTS = 4,
    RAC_EVENT_CATEGORY_VOICE = 5,
    RAC_EVENT_CATEGORY_STORAGE = 6,
    RAC_EVENT_CATEGORY_DEVICE = 7,
    RAC_EVENT_CATEGORY_NETWORK = 8,
    RAC_EVENT_CATEGORY_ERROR = 9,
} rac_event_category_t;

// =============================================================================
// EVENT STRUCTURE - Mirrors Swift's SDKEvent protocol
// =============================================================================

/**
 * Event data structure.
 * Mirrors Swift's SDKEvent protocol properties.
 */
typedef struct rac_event {
    /** Unique identifier for this event instance */
    const char* id;

    /** Event type string (used for analytics categorization) */
    const char* type;

    /** Category for filtering/routing */
    rac_event_category_t category;

    /** Timestamp in milliseconds since epoch */
    int64_t timestamp_ms;

    /** Optional session ID for grouping related events (can be NULL) */
    const char* session_id;

    /** Where to route this event */
    rac_event_destination_t destination;

    /** Event properties as JSON string (can be NULL) */
    const char* properties_json;
} rac_event_t;

// =============================================================================
// EVENT CALLBACK
// =============================================================================

/**
 * Event callback function type.
 *
 * @param event The event data (valid only during the callback)
 * @param user_data User-provided context data
 */
typedef void (*rac_event_callback_fn)(const rac_event_t* event, void* user_data);

// =============================================================================
// EVENT API
// =============================================================================

/**
 * Subscribes to events of a specific category.
 *
 * @param category The category to subscribe to
 * @param callback The callback function to invoke
 * @param user_data User data passed to the callback
 * @return Subscription ID (0 on failure), use with rac_event_unsubscribe
 *
 * @note The callback is invoked on the thread that publishes the event.
 *       Keep callback execution fast to avoid blocking.
 */
RAC_API uint64_t rac_event_subscribe(rac_event_category_t category, rac_event_callback_fn callback,
                                     void* user_data);

/**
 * Subscribes to all events regardless of category.
 *
 * @param callback The callback function to invoke
 * @param user_data User data passed to the callback
 * @return Subscription ID (0 on failure)
 */
RAC_API uint64_t rac_event_subscribe_all(rac_event_callback_fn callback, void* user_data);

/**
 * Unsubscribes from events.
 *
 * @param subscription_id The subscription ID returned from subscribe
 */
RAC_API void rac_event_unsubscribe(uint64_t subscription_id);

/**
 * Publishes an event to all subscribers.
 *
 * This is called by the commons library to publish events.
 * Swift's EventBridge subscribes to receive and re-publish to Swift consumers.
 *
 * @param event The event to publish
 * @return RAC_SUCCESS on success, or an error code on failure
 */
RAC_API rac_result_t rac_event_publish(const rac_event_t* event);

/**
 * Track an event (convenience function matching Swift's EventPublisher.track).
 *
 * @param type Event type string
 * @param category Event category
 * @param destination Where to route this event
 * @param properties_json Event properties as JSON (can be NULL)
 * @return RAC_SUCCESS on success, or an error code on failure
 */
RAC_API rac_result_t rac_event_track(const char* type, rac_event_category_t category,
                                     rac_event_destination_t destination,
                                     const char* properties_json);

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

/**
 * Gets a string name for an event category.
 *
 * @param category The event category
 * @return A string name (never NULL)
 */
RAC_API const char* rac_event_category_name(rac_event_category_t category);

#ifdef __cplusplus
}
#endif

#endif /* RAC_EVENTS_H */
