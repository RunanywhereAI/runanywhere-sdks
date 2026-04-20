// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_telemetry.h"

#include "../net/telemetry.h"

#include <atomic>
#include <mutex>
#include <string>

namespace {
std::mutex                          g_mu;
ra_telemetry_http_callback_t        g_cb       = nullptr;
void*                               g_user     = nullptr;
}  // namespace

extern "C" {

ra_status_t ra_telemetry_set_http_callback(ra_telemetry_http_callback_t cb,
                                            void* user_data) {
    std::lock_guard lock(g_mu);
    g_cb   = cb;
    g_user = user_data;
    return RA_OK;
}

ra_status_t ra_telemetry_flush(void) {
    // The C++ TelemetryManager flushes on `stop()`. Frontends that need
    // explicit flush call this; we call stop+start under the hood.
    auto& mgr = ra::core::net::TelemetryManager::global();
    mgr.stop();
    mgr.start();
    return RA_OK;
}

ra_status_t ra_telemetry_track(const char* event_name,
                                const char* /*properties_json*/) {
    if (!event_name) return RA_ERR_INVALID_ARGUMENT;
    ra::core::net::TelemetryEvent ev;
    ev.name = event_name;
    ra::core::net::TelemetryManager::global().emit(std::move(ev));
    return RA_OK;
}

}  // extern "C"
