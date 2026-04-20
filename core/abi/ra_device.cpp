// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_device.h"
#include "ra_state.h"

#include <atomic>
#include <cstdlib>
#include <cstring>
#include <mutex>

namespace {
std::mutex                g_mu;
ra_device_callbacks_t     g_cbs{};
bool                      g_set = false;

char* dup_cstr(const char* s) {
    if (!s) return nullptr;
    const std::size_t n = std::strlen(s);
    char* out = static_cast<char*>(std::malloc(n + 1));
    if (!out) return nullptr;
    std::memcpy(out, s, n + 1);
    return out;
}
}  // namespace

extern "C" {

ra_status_t ra_device_manager_set_callbacks(const ra_device_callbacks_t* callbacks) {
    if (!callbacks) return RA_ERR_INVALID_ARGUMENT;
    std::lock_guard lock(g_mu);
    g_cbs = *callbacks;
    g_set = true;
    return RA_OK;
}

uint8_t ra_device_manager_is_registered(void) {
    return ra_state_is_device_registered();
}

ra_status_t ra_device_manager_register_if_needed(void) {
    if (ra_device_manager_is_registered()) return RA_OK;
    std::lock_guard lock(g_mu);
    if (!g_set || !g_cbs.get_device_id) return RA_ERR_BACKEND_UNAVAILABLE;
    char* device_id = nullptr;
    auto rc = g_cbs.get_device_id(&device_id, g_cbs.user_data);
    if (rc != RA_OK || !device_id) return rc != RA_OK ? rc : RA_ERR_INTERNAL;
    // The actual cloud-side registration call is the responsibility of the
    // platform bridge (uses HTTP via ra_state_initialize). We mark the device
    // as registered locally; the bridge invokes `on_registered` after its
    // own handshake.
    ra_state_set_device_registered(1);
    if (g_cbs.on_registered) {
        const char* api = ra_state_get_api_key();
        g_cbs.on_registered(device_id, api ? api : "", g_cbs.user_data);
    }
    std::free(device_id);
    return RA_OK;
}

ra_status_t ra_device_manager_clear_registration(void) {
    std::lock_guard lock(g_mu);
    ra_state_set_device_registered(0);
    if (g_set && g_cbs.on_cleared) g_cbs.on_cleared(g_cbs.user_data);
    return RA_OK;
}

ra_status_t ra_device_manager_get_device_id(char** out_device_id) {
    if (!out_device_id) return RA_ERR_INVALID_ARGUMENT;
    const char* id = ra_state_get_device_id();
    if (!id || !*id) {
        std::lock_guard lock(g_mu);
        if (g_set && g_cbs.get_device_id) {
            char* tmp = nullptr;
            auto rc = g_cbs.get_device_id(&tmp, g_cbs.user_data);
            if (rc == RA_OK && tmp) {
                *out_device_id = tmp;  // ownership transferred
                return RA_OK;
            }
        }
        return RA_ERR_CAPABILITY_UNSUPPORTED;
    }
    *out_device_id = dup_cstr(id);
    return *out_device_id ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

void ra_device_string_free(char* s) { if (s) std::free(s); }

}  // extern "C"
