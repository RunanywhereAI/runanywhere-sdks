/**
 * @file rac_events.h
 * @brief RunAnywhere Commons - Internal lower-level category event publisher.
 *
 * Classification (see docs/CPP_PROTO_OWNERSHIP.md): `internal`.
 *
 * Lock-copy-dispatch category-keyed pub/sub used inside commons by lifecycle
 * manager, storage analyzer, device manager, and engine plugins for
 * fine-grained backend telemetry breadcrumbs. It is NOT the SDK-facing event
 * surface. SDK consumers MUST use the canonical SDKEvent proto-byte stream in
 * `rac/infrastructure/events/rac_sdk_event_stream.h`.
 *
 * Coexistence:
 *   - `rac_event_publish` / `rac_event_subscribe` carry the older
 *     `rac_event_t` struct (string `type`, JSON `properties_json`).
 *   - `rac_sdk_event_publish_proto` carries serialized `runanywhere.v1.SDKEvent`
 *     bytes. This is the canonical SDK surface.
 *
 * Bridge: components that already emit through this channel ALSO emit a
 * canonical SDKEvent through `rac_sdk_event_publish_proto`. The legacy struct
 * stream stays alive only for engine-internal breadcrumbs that are still being
 * migrated to typed proto fields under `SDKEvent.telemetry`.
 */

#ifndef RAC_EVENTS_H
#define RAC_EVENTS_H

// ---------------------------------------------------------------------------
// Internal-use guard. Defined automatically when commons or engines build
// against the C++ source tree. Public SDK headers MUST NOT include this file.
// ---------------------------------------------------------------------------
#if !defined(RAC_ALLOW_INTERNAL_EVENTS) && !defined(RAC_BUILDING_COMMONS) &&    \
    !defined(RAC_INTERNAL_TRANSLATION_UNIT)
#warning "rac_events.h is an internal commons header. Public SDK code must subscribe to canonical SDKEvent bytes via rac_sdk_event_stream.h. Define RAC_ALLOW_INTERNAL_EVENTS only inside engine plugins or commons internals."
#endif

#include "rac/core/rac_types.h"

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
