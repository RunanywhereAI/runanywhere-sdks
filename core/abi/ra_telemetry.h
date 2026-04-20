// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — telemetry C ABI.
//
// Lets the platform bridge inject an HTTP uploader for telemetry events
// (so we don't need libcurl on iOS / Android). Wraps `core/net/telemetry.h`.

#ifndef RA_TELEMETRY_H
#define RA_TELEMETRY_H

#include <stddef.h>
#include <stdint.h>

#include "ra_primitives.h"

#ifdef __cplusplus
extern "C" {
#endif

// Platform-supplied uploader. The core hands the JSON payload to the bridge
// which POSTs it via URLSession / OkHttp / fetch.
typedef ra_status_t (*ra_telemetry_http_callback_t)(const char* endpoint_url,
                                                     const char* json_body,
                                                     void* user_data);

ra_status_t ra_telemetry_set_http_callback(ra_telemetry_http_callback_t cb,
                                            void* user_data);

// Force-flush any buffered telemetry events to the registered uploader.
ra_status_t ra_telemetry_flush(void);

// Track an arbitrary event from the frontend (e.g. "model_loaded",
// "voice_session_started"). `properties_json` is an optional JSON object.
ra_status_t ra_telemetry_track(const char* event_name,
                                const char* properties_json);

// ---------------------------------------------------------------------------
// Device registration payload helpers
// ---------------------------------------------------------------------------

typedef struct ra_device_registration_info_s {
    const char* device_id;
    const char* os_name;          // "iOS", "macOS", "Android", etc.
    const char* os_version;
    const char* app_version;
    const char* sdk_version;
    const char* model_name;       // e.g. "iPhone15,2"
    const char* chip_name;        // e.g. "Apple A17 Pro"
    int64_t     total_memory_bytes;
    int64_t     available_storage_bytes;
} ra_device_registration_info_t;

// Returns the canonical device-registration endpoint URL. Thread-local
// pointer; valid until next call.
const char* ra_device_registration_endpoint(void);

// Serialises a `ra_device_registration_info_t` to JSON. Heap-allocated;
// free with `ra_telemetry_string_free`.
ra_status_t ra_device_registration_to_json(
    const ra_device_registration_info_t* info, char** out_json);

// ---------------------------------------------------------------------------
// Generic payload / batch helpers
// ---------------------------------------------------------------------------

// Returns a default-populated telemetry payload JSON. Heap-allocated.
// Frontends typically merge this with event-specific properties.
ra_status_t ra_telemetry_payload_default(char** out_json);

// Parses a batch response from the server (e.g. `{"accepted": 42}`).
// Returns RA_OK + populates `out_accepted` / `out_rejected` on success.
ra_status_t ra_telemetry_parse_response(const char* json_body,
                                         int32_t* out_accepted,
                                         int32_t* out_rejected);

// Serialises the current in-memory queue to a batch JSON envelope.
// Useful for tests and for one-shot upload without starting the manager.
ra_status_t ra_telemetry_batch_to_json(char** out_json);

// Helper to convert an arbitrary {key, value_string} map to a JSON
// properties object. `pairs` is a flat array [k0, v0, k1, v1, ...].
ra_status_t ra_telemetry_properties_to_json(const char* const* pairs,
                                             int32_t            pair_count,
                                             char**             out_json);

void ra_telemetry_string_free(char* str);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_TELEMETRY_H
