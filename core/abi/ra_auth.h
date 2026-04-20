// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Auth manager C ABI — public surface matching legacy `rac_auth_*`.
// Wraps core/net/environment.{h,cpp} `AuthManager` singleton.
//
// Frontends bridging to a cloud auth service use this to:
//   - read/write access + refresh tokens
//   - check expiry + `needs_refresh` horizon
//   - build canonical authenticate / refresh request JSON payloads
//   - parse the server's response JSON into tokens
//   - persist tokens via the platform adapter's secure_* callbacks

#ifndef RA_AUTH_H
#define RA_AUTH_H

#include <stddef.h>
#include <stdint.h>

#include "ra_primitives.h"

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

// Initializes auth state. Optional — the underlying singleton is lazy-
// initialized on first access. Provided for API-shape parity with main.
ra_status_t ra_auth_init(void);

// Clear tokens + reset registered flag. Does NOT clear the api_key —
// use ra_state_reset for that.
ra_status_t ra_auth_reset(void);

// ---------------------------------------------------------------------------
// State queries
// ---------------------------------------------------------------------------

// 1 iff access_token is present and unexpired.
uint8_t ra_auth_is_authenticated(void);

// 1 iff access token expires within `horizon_seconds` (default 60 if 0).
uint8_t ra_auth_needs_refresh(int32_t horizon_seconds);

// Returns the current access / refresh / user / org id, or empty string.
// Pointer is valid until the next call to the same getter on this thread.
const char* ra_auth_get_access_token(void);
const char* ra_auth_get_refresh_token(void);
const char* ra_auth_get_device_id(void);
const char* ra_auth_get_user_id(void);
const char* ra_auth_get_organization_id(void);

// ---------------------------------------------------------------------------
// JSON request / response shaping
// ---------------------------------------------------------------------------

// Build an `authenticate` request body (JSON). Heap-allocated; free with
// ra_auth_string_free.
ra_status_t ra_auth_build_authenticate_request(const char* api_key,
                                                 const char* device_id,
                                                 char**      out_body);

// Build a `refresh` request body (JSON) using the stored refresh token.
ra_status_t ra_auth_build_refresh_request(char** out_body);

// Parse an authenticate response body and set tokens. Returns RA_OK on
// success; tokens are populated from the JSON.
ra_status_t ra_auth_handle_authenticate_response(const char* json_body);

// Same for a refresh response.
ra_status_t ra_auth_handle_refresh_response(const char* json_body);

// ---------------------------------------------------------------------------
// Token lifecycle convenience
// ---------------------------------------------------------------------------

// Returns a valid access token, refreshing via the persist/load platform
// adapter hooks if needed. Pointer is thread-local; treat as transient.
// Returns NULL if no valid token is available and refresh is not possible.
const char* ra_auth_get_valid_token(void);

// Clear tokens (same as ra_auth_reset but does NOT touch device_id).
void ra_auth_clear(void);

// Load persisted tokens from the platform adapter's load callback.
// Returns RA_OK if at least an access_token was loaded.
ra_status_t ra_auth_load_stored_tokens(void);

// Persist current tokens via the platform adapter's persist callback.
ra_status_t ra_auth_save_tokens(void);

// Free a heap-allocated string returned by any helper above.
void ra_auth_string_free(char* str);

#ifdef __cplusplus
}
#endif

#endif  // RA_AUTH_H
