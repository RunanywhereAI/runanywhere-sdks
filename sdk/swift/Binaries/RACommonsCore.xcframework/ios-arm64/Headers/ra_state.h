// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — SDK state C ABI.
//
// Legacy commons used a single `rac_state_*` namespace to query auth
// tokens, environment, device id, etc. New core splits these across
// AuthManager + Environment (see core/net/environment.h). This header
// exposes a thin C ABI that delegates to the C++ singletons, matching
// the legacy API shape so Swift / Kotlin bridges continue to work.

#ifndef RA_STATE_H
#define RA_STATE_H

#include <stdbool.h>
#include <stdint.h>

#include "ra_primitives.h"

#ifdef __cplusplus
extern "C" {
#endif

// --- Environment -----------------------------------------------------------
typedef int32_t ra_environment_t;
enum {
    RA_ENVIRONMENT_DEVELOPMENT = 0,
    RA_ENVIRONMENT_STAGING     = 1,
    RA_ENVIRONMENT_PRODUCTION  = 2,
};

// --- Auth tokens passed to ra_state_set_auth -------------------------------
typedef struct {
    const char*  access_token;
    const char*  refresh_token;
    int64_t      expires_at_unix;   // 0 = no declared expiry
    const char*  user_id;            // may be NULL
    const char*  organization_id;    // may be NULL
    const char*  device_id;          // may be NULL
} ra_auth_data_t;

// --- Initialization --------------------------------------------------------
//
// Called once at startup by the Swift/Kotlin SDK bootstrap. Stores
// api_key, base_url, device_id, env. After ra_state_initialize returns
// RA_OK, the AuthManager singleton is ready to serve queries.
ra_status_t ra_state_initialize(ra_environment_t env, const char* api_key,
                                 const char* base_url, const char* device_id);

bool        ra_state_is_initialized(void);

// Wipes api_key, tokens, device_registered flag. Environment + base URL
// are preserved (use ra_state_initialize again to change those).
void        ra_state_reset(void);

// Alias for ra_shutdown. Kept so the legacy `rac_state_shutdown` call
// sites continue to work.
void        ra_state_shutdown(void);

// --- Environment / base URL / api key queries ------------------------------
ra_environment_t  ra_state_get_environment(void);
const char*       ra_state_get_base_url(void);
const char*       ra_state_get_api_key(void);
const char*       ra_state_get_device_id(void);

// --- Auth token lifecycle --------------------------------------------------
ra_status_t ra_state_set_auth(const ra_auth_data_t* auth);
const char* ra_state_get_access_token(void);
const char* ra_state_get_refresh_token(void);
bool        ra_state_is_authenticated(void);
bool        ra_state_token_needs_refresh(int horizon_seconds);
int64_t     ra_state_get_token_expires_at(void);
const char* ra_state_get_user_id(void);
const char* ra_state_get_organization_id(void);
void        ra_state_clear_auth(void);

// --- Device registration state --------------------------------------------
void        ra_state_set_device_registered(bool registered);
bool        ra_state_is_device_registered(void);

// --- Auth-change observer --------------------------------------------------
//
// Called when set_auth / clear_auth flips the is_authenticated bit.
// Thread-safety: the callback fires on the thread that triggered the
// change. Registering NULL clears the current observer.
typedef void (*ra_auth_changed_callback_t)(bool is_authenticated, void* user_data);

void ra_state_on_auth_changed(ra_auth_changed_callback_t callback, void* user_data);

// --- Persistence bridge ----------------------------------------------------
//
// Platform-provided secure-storage callbacks. The core calls `persist`
// whenever a token changes, and `load` during ra_state_initialize to
// rehydrate previously-stored tokens. When unregistered, the core
// doesn't persist tokens — each process starts with a clean slate.
typedef void        (*ra_state_persist_callback_t)(const char* key,
                                                     const char* value,
                                                     void*       user_data);
typedef const char* (*ra_state_load_callback_t)(const char* key,
                                                  void*       user_data);

void ra_state_set_persistence_callbacks(ra_state_persist_callback_t persist,
                                         ra_state_load_callback_t    load,
                                         void*                       user_data);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_STATE_H
