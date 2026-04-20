// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — events bus C ABI.
//
// Lightweight observer surface so frontends can subscribe to SDK
// lifecycle / model / generation events emitted from the C++ core
// (download progress, model loaded, generation token, etc.). Mirrors
// the legacy `rac_event_*` + `rac_analytics_events_*` callback hooks.

#ifndef RA_EVENT_H
#define RA_EVENT_H

#include <stddef.h>
#include <stdint.h>

#include "ra_primitives.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t ra_event_category_t;
enum {
    RA_EVENT_CATEGORY_UNKNOWN     = 0,
    RA_EVENT_CATEGORY_LIFECYCLE   = 1,
    RA_EVENT_CATEGORY_MODEL       = 2,
    RA_EVENT_CATEGORY_LLM         = 3,
    RA_EVENT_CATEGORY_STT         = 4,
    RA_EVENT_CATEGORY_TTS         = 5,
    RA_EVENT_CATEGORY_VAD         = 6,
    RA_EVENT_CATEGORY_VOICE_AGENT = 7,
    RA_EVENT_CATEGORY_DOWNLOAD    = 8,
    RA_EVENT_CATEGORY_TELEMETRY   = 9,
    RA_EVENT_CATEGORY_ERROR       = 10,
    // Additions to mirror main's taxonomy:
    RA_EVENT_CATEGORY_STORAGE     = 11,   // file I/O / cache / archive extract
    RA_EVENT_CATEGORY_DEVICE      = 12,   // hardware profile / battery / thermal
    RA_EVENT_CATEGORY_NETWORK     = 13,   // HTTP / auth / telemetry transport
    RA_EVENT_CATEGORY_VOICE       = 14,   // generic voice-session (user_said, etc.)
};

typedef struct {
    ra_event_category_t category;
    const char*         name;            // e.g. "model.loaded"
    const char*         payload_json;    // Optional JSON payload
    int64_t             timestamp_ms;
} ra_event_t;

typedef int32_t ra_event_subscription_id_t;

typedef void (*ra_event_callback_fn)(const ra_event_t* event, void* user_data);

// Subscribe to events of a single category. Returns a subscription id; use
// `ra_event_unsubscribe` to detach. Returns -1 on error.
ra_event_subscription_id_t ra_event_subscribe(ra_event_category_t  category,
                                                ra_event_callback_fn cb,
                                                void*                user_data);

// Subscribe to ALL events.
ra_event_subscription_id_t ra_event_subscribe_all(ra_event_callback_fn cb,
                                                    void*                user_data);

ra_status_t ra_event_unsubscribe(ra_event_subscription_id_t id);

// Set/clear the single global callback (legacy `rac_events_set_callback`).
ra_status_t ra_event_set_callback(ra_event_callback_fn cb, void* user_data);

// Set/clear the analytics-only callback (subset of events tagged for analytics).
ra_status_t ra_analytics_events_set_callback(ra_event_callback_fn cb,
                                              void* user_data);
ra_status_t ra_analytics_events_set_public_callback(ra_event_callback_fn cb,
                                                     void* user_data);

// Internal — used by the core to publish events. Frontends should not call
// this; the dispatcher fans out to every subscriber.
void ra_event_publish(const ra_event_t* event);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_EVENT_H
