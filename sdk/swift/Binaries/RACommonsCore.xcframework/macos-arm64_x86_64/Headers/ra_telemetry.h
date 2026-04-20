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

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_TELEMETRY_H
