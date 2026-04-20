// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — device manager C ABI.
//
// Wraps the device-registration callbacks that the platform bridge uses
// to register the device with the cloud (one-shot at first launch).
// Mirrors the legacy `rac_device_manager_*` callback table.

#ifndef RA_DEVICE_H
#define RA_DEVICE_H

#include <stddef.h>
#include <stdint.h>

#include "ra_primitives.h"

#ifdef __cplusplus
extern "C" {
#endif

// Callbacks the platform bridge fills in. The core invokes them when
// `ra_device_manager_register_if_needed` is called and the device hasn't
// yet been registered with the cloud.
typedef struct ra_device_callbacks_s {
    // Returns the persistent device ID (e.g. iOS identifierForVendor /
    // Android Settings.Secure.ANDROID_ID). The string buffer is owned by
    // the callback; the core copies it.
    ra_status_t (*get_device_id)(char**     out_device_id, void* user_data);

    // Called once after a successful cloud registration; the platform bridge
    // typically persists this to Keychain / KeyStore.
    void        (*on_registered)(const char* device_id, const char* api_key,
                                  void* user_data);

    // Called when the user clears registration (e.g. settings → reset SDK).
    void        (*on_cleared)(void* user_data);

    void* user_data;
} ra_device_callbacks_t;

ra_status_t ra_device_manager_set_callbacks(const ra_device_callbacks_t* callbacks);

// Returns 1 if the device is already registered (delegates to ra_state_*).
uint8_t     ra_device_manager_is_registered(void);

// Triggers registration if not already registered. Synchronous; returns
// RA_OK once the cloud handshake completes (or RA_ERR_BACKEND_UNAVAILABLE
// when no callbacks are set).
ra_status_t ra_device_manager_register_if_needed(void);

// Clears registration state (both cloud-side flag and persistent storage).
ra_status_t ra_device_manager_clear_registration(void);

// Returns a heap-allocated copy of the device ID; free with `ra_device_string_free`.
ra_status_t ra_device_manager_get_device_id(char** out_device_id);

void ra_device_string_free(char* s);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_DEVICE_H
