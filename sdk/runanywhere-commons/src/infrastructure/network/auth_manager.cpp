/**
 * @file auth_manager.cpp
 * @brief Authentication state management implementation
 */

#include <cstdlib>
#include <cstring>
#include <ctime>
#include <mutex>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/infrastructure/network/rac_api_types.h"
#include "rac/infrastructure/network/rac_auth_manager.h"

#include "rac/core/rac_sdk_state.h"
#include "rac/infrastructure/device/rac_device_manager.h"

#include "../device/rac_device_live_state_internal.h"

// =============================================================================
// Global State
// =============================================================================

// commons-005: every read/write of g_auth_state, g_storage, g_storage_available
// must hold g_auth_mutex. Refresh fires asynchronously from a timer; sign-out
// can happen from any UI thread; HTTP layer reads token on every request.
// Without this lock, rac_auth_clear() can free strings still pointed at by
// callers, and concurrent writes corrupt the state struct.
static std::mutex g_auth_mutex;
static rac_auth_state_t g_auth_state = {};
static rac_secure_storage_t g_storage = {};
static bool g_storage_available = false;

// =============================================================================
// Helpers
// =============================================================================

// Caller must hold g_auth_mutex.
static void free_auth_state_strings_locked() {
    free(g_auth_state.access_token);
    free(g_auth_state.refresh_token);
    free(g_auth_state.device_id);
    free(g_auth_state.user_id);
    free(g_auth_state.organization_id);

    g_auth_state.access_token = nullptr;
    g_auth_state.refresh_token = nullptr;
    g_auth_state.device_id = nullptr;
    g_auth_state.user_id = nullptr;
    g_auth_state.organization_id = nullptr;
}

// Caller must hold g_auth_mutex.
static void reset_auth_state_locked() {
    free_auth_state_strings_locked();
    memset(&g_auth_state, 0, sizeof(g_auth_state));
}

static int64_t current_time_seconds() {
    return (int64_t)time(nullptr);
}

// Caller must hold g_auth_mutex (touches no globals but kept local for symmetry).
static const char* auth_subject_id(const rac_auth_response_t* response) {
    if (!response) {
        return nullptr;
    }
    if (response->user_id && response->user_id[0] != '\0') {
        return response->user_id;
    }
    if (response->organization_id && response->organization_id[0] != '\0') {
        return response->organization_id;
    }
    return nullptr;
}

static void publish_auth_success_event(const rac_auth_response_t* response, bool refresh) {
    const char* operation = refresh ? "auth.refresh" : "auth.authenticate";
    if (refresh) {
        rac::events::publish_auth_token_refreshed(auth_subject_id(response), "runanywhere", "sdk",
                                                  operation,
                                                  response ? response->device_id : nullptr);
    } else {
        rac::events::publish_auth_succeeded(auth_subject_id(response), "runanywhere", "sdk",
                                            operation, response ? response->device_id : nullptr);
    }
}

static void publish_auth_failure_event(const char* message, bool refresh,
                                       rac_result_t code = RAC_ERROR_AUTHENTICATION_FAILED) {
    rac::events::publish_auth_failed(code, message ? message : "Authentication failed",
                                     "runanywhere", "sdk",
                                     refresh ? "auth.refresh" : "auth.authenticate");
}

// Caller must hold g_auth_mutex. Mirrors rac_auth_is_authenticated() without
// re-locking so authenticated checks performed inside the lock stay consistent.
static bool is_authenticated_locked() {
    return g_auth_state.is_authenticated && g_auth_state.access_token != nullptr &&
           g_auth_state.access_token[0] != '\0';
}

// Caller must hold g_auth_mutex. Mirrors rac_auth_save_tokens(); extracted so
// handle_auth_response() can persist atomically without releasing the lock.
static int save_tokens_locked() {
    if (!g_storage_available) {
        return RAC_SUCCESS;
    }

    int result = RAC_SUCCESS;

    // Persist an exact snapshot, including removal of optional values omitted
    // by a later refresh response. Otherwise a future process launch could
    // restore stale device/user/organization identity from an older response.
    const auto persist = [&](const char* key, const char* value) {
        const int operation_result = value ? g_storage.store(key, value, g_storage.context)
                                           : g_storage.delete_key(key, g_storage.context);
        if (operation_result != 0) {
            result = RAC_ERROR_SECURE_STORAGE_FAILED;
        }
    };
    persist(RAC_KEY_ACCESS_TOKEN, g_auth_state.access_token);
    persist(RAC_KEY_REFRESH_TOKEN, g_auth_state.refresh_token);
    persist(RAC_KEY_DEVICE_ID, g_auth_state.device_id);
    persist(RAC_KEY_USER_ID, g_auth_state.user_id);
    persist(RAC_KEY_ORGANIZATION_ID, g_auth_state.organization_id);

    return result;
}

// Caller must hold g_auth_mutex. Every key is attempted even after a failure
// so logout and rollback cannot leave avoidable credential fragments behind.
static rac_result_t delete_stored_auth_locked() {
    if (!g_storage_available) {
        return RAC_SUCCESS;
    }

    rac_result_t result = RAC_SUCCESS;
    const auto delete_key = [&](const char* key) {
        if (g_storage.delete_key(key, g_storage.context) != 0) {
            result = RAC_ERROR_SECURE_STORAGE_FAILED;
        }
    };
    delete_key(RAC_KEY_ACCESS_TOKEN);
    delete_key(RAC_KEY_REFRESH_TOKEN);
    delete_key(RAC_KEY_DEVICE_ID);
    delete_key(RAC_KEY_USER_ID);
    delete_key(RAC_KEY_ORGANIZATION_ID);
    return result;
}

// =============================================================================
// Initialization
// =============================================================================

void rac_auth_init(const rac_secure_storage_t* storage) {
    std::lock_guard<std::mutex> lock(g_auth_mutex);
    reset_auth_state_locked();

    if (storage && storage->store && storage->retrieve && storage->delete_key) {
        g_storage = *storage;
        g_storage_available = true;
    } else {
        memset(&g_storage, 0, sizeof(g_storage));
        g_storage_available = false;
    }
}

void rac_auth_reset(void) {
    std::lock_guard<std::mutex> lock(g_auth_mutex);
    reset_auth_state_locked();
}

// =============================================================================
// Token State
// =============================================================================

bool rac_auth_is_authenticated(void) {
    std::lock_guard<std::mutex> lock(g_auth_mutex);
    return is_authenticated_locked();
}

bool rac_auth_needs_refresh(void) {
    std::lock_guard<std::mutex> lock(g_auth_mutex);
    if (!g_auth_state.refresh_token || g_auth_state.refresh_token[0] == '\0') {
        return false;  // Can't refresh without refresh token
    }

    if (g_auth_state.token_expires_at <= 0) {
        return true;  // Unknown expiry, assume needs refresh
    }

    // Check if token expires within 60 seconds
    int64_t now = current_time_seconds();
    return (g_auth_state.token_expires_at - now) < 60;
}

// commons-005: getters copy under the lock into a thread_local buffer so the
// returned pointer remains valid even if another thread calls rac_auth_clear()
// or handle_auth_response() right after we return. Mirrors the proven pattern
// in sdk_state.cpp / model_paths.cpp. Contract: pointer is valid until the
// next rac_auth_* call on this thread.
const char* rac_auth_get_access_token(void) {
    static thread_local std::string tl_access_token;
    std::lock_guard<std::mutex> lock(g_auth_mutex);
    if (!is_authenticated_locked()) {
        return nullptr;
    }
    tl_access_token = g_auth_state.access_token;
    return tl_access_token.c_str();
}

const char* rac_auth_get_refresh_token(void) {
    static thread_local std::string tl_refresh_token;
    std::lock_guard<std::mutex> lock(g_auth_mutex);
    if (!g_auth_state.refresh_token || g_auth_state.refresh_token[0] == '\0') {
        return nullptr;
    }
    tl_refresh_token = g_auth_state.refresh_token;
    return tl_refresh_token.c_str();
}

int64_t rac_auth_get_token_expires_at(void) {
    std::lock_guard<std::mutex> lock(g_auth_mutex);
    return g_auth_state.token_expires_at;
}

const char* rac_auth_get_device_id(void) {
    static thread_local std::string tl_device_id;
    std::lock_guard<std::mutex> lock(g_auth_mutex);
    if (!g_auth_state.device_id) {
        return nullptr;
    }
    tl_device_id = g_auth_state.device_id;
    return tl_device_id.c_str();
}

const char* rac_auth_get_user_id(void) {
    static thread_local std::string tl_user_id;
    std::lock_guard<std::mutex> lock(g_auth_mutex);
    if (!g_auth_state.user_id) {
        return nullptr;
    }
    tl_user_id = g_auth_state.user_id;
    return tl_user_id.c_str();
}

const char* rac_auth_get_organization_id(void) {
    static thread_local std::string tl_organization_id;
    std::lock_guard<std::mutex> lock(g_auth_mutex);
    if (!g_auth_state.organization_id) {
        return nullptr;
    }
    tl_organization_id = g_auth_state.organization_id;
    return tl_organization_id.c_str();
}

// =============================================================================
// Request Building
// =============================================================================

char* rac_auth_build_authenticate_request(const rac_sdk_config_t* config) {
    if (!config)
        return nullptr;

    rac_auth_request_t request = {};
    request.api_key = config->api_key;
    request.device_id = config->device_id;
    request.platform = config->platform;
    request.sdk_version = config->sdk_version;

    return rac_auth_request_to_json(&request);
}

char* rac_auth_build_refresh_request(void) {
    // Snapshot the two strings under the lock then build the JSON outside —
    // rac_refresh_request_to_json() allocates and is independent of globals.
    std::string device_id_copy;
    std::string refresh_token_copy;
    {
        std::lock_guard<std::mutex> lock(g_auth_mutex);
        if (!g_auth_state.refresh_token || !g_auth_state.device_id) {
            return nullptr;
        }
        device_id_copy = g_auth_state.device_id;
        refresh_token_copy = g_auth_state.refresh_token;
    }

    rac_refresh_request_t request = {};
    request.device_id = device_id_copy.c_str();
    request.refresh_token = refresh_token_copy.c_str();

    return rac_refresh_request_to_json(&request);
}

// =============================================================================
// Response Handling
// =============================================================================

// Caller must hold g_auth_mutex.
static int update_auth_state_from_response_locked(const rac_auth_response_t* response) {
    if (!response || !response->access_token || !response->refresh_token) {
        return -1;
    }

    // Pre-allocate required strings before modifying state
    char* new_access = rac_strdup(response->access_token);
    char* new_refresh = rac_strdup(response->refresh_token);
    if (!new_access || !new_refresh) {
        free(new_access);
        free(new_refresh);
        return -1;
    }

    // Free old strings
    free_auth_state_strings_locked();

    // Assign pre-allocated required values
    g_auth_state.access_token = new_access;
    g_auth_state.refresh_token = new_refresh;

    // Copy optional values (NULL is acceptable)
    g_auth_state.device_id = rac_strdup(response->device_id);
    g_auth_state.user_id = rac_strdup(response->user_id);
    g_auth_state.organization_id = rac_strdup(response->organization_id);

    // Calculate expiry timestamp
    g_auth_state.token_expires_at = current_time_seconds() + response->expires_in;
    g_auth_state.is_authenticated = true;

    return 0;
}

static int handle_auth_response(const char* json, bool refresh) {
    if (!json) {
        publish_auth_failure_event("Authentication response body is missing", refresh);
        return -1;
    }

    rac_auth_response_t response = {};
    if (rac_auth_response_from_json(json, &response) != 0) {
        publish_auth_failure_event("Authentication response is invalid", refresh);
        return -1;
    }

    // Registration heal: the authenticate response reports
    // device_registered=false when the backend only holds a placeholder row
    // for this device. Flag the device manager so the phase-2 registration
    // runs even when the platform-persisted is_registered flag says otherwise.
    // Absent field (older backends) means no override.
    const bool server_unregistered =
        !refresh && (strstr(json, "\"device_registered\":false") != nullptr ||
                     strstr(json, "\"device_registered\": false") != nullptr);
    if (server_unregistered) {
        rac_device_manager_notify_server_unregistered();
    }

    int result;
    {
        std::lock_guard<std::mutex> lock(g_auth_mutex);
        result = update_auth_state_from_response_locked(&response);

        // Save to secure storage atomically while still holding the lock so
        // we cannot race a concurrent rac_auth_clear() between the in-memory
        // update and the persisted copy.
        if (result == RAC_SUCCESS) {
            result = save_tokens_locked();
            if (result != RAC_SUCCESS) {
                // A partial durable write is not authenticated state. Fail
                // closed, clear process memory, and best-effort delete every
                // auth key before returning the persistence failure.
                reset_auth_state_locked();
                (void)delete_stored_auth_locked();
            }
        }
    }

    // Publish events outside the lock (lock-copy-dispatch) — subscribers may
    // re-enter auth APIs (e.g. to log token state) so holding the mutex would
    // deadlock.
    if (result == RAC_SUCCESS) {
        publish_auth_success_event(&response, refresh);
        // A token is now available — drain telemetry batches deferred by the
        // pre-auth flush gate (see rac_telemetry_manager_flush).
        rac_events_flush_telemetry_sink();
        // The freshly minted token is now available: run the forced
        // registration immediately so the server's placeholder row upgrades
        // this session instead of on the next launch.
        if (server_unregistered) {
            (void)rac_device_manager_register_if_needed(rac_state_get_environment(), nullptr);
        }
    } else {
        if (result == RAC_ERROR_SECURE_STORAGE_FAILED) {
            publish_auth_failure_event("Failed to persist authentication state", refresh,
                                       RAC_ERROR_SECURE_STORAGE_FAILED);
        } else {
            publish_auth_failure_event("Failed to update authentication state", refresh);
        }
    }

    rac_auth_response_free(&response);
    return result;
}

int rac_auth_handle_authenticate_response(const char* json) {
    return handle_auth_response(json, false);
}

int rac_auth_handle_refresh_response(const char* json) {
    // Same response format as authenticate; event semantics are distinct.
    return handle_auth_response(json, true);
}

// =============================================================================
// Token Management
// =============================================================================

int rac_auth_get_valid_token(const char** out_token, bool* out_needs_refresh) {
    if (!out_token || !out_needs_refresh)
        return -1;

    *out_token = nullptr;
    *out_needs_refresh = false;

    // commons-005: copy the token under the lock into a thread_local buffer so
    // the *out_token pointer remains valid after we drop the lock.
    static thread_local std::string tl_valid_token;
    std::lock_guard<std::mutex> lock(g_auth_mutex);

    if (!is_authenticated_locked()) {
        return -1;
    }

    if (g_auth_state.refresh_token && g_auth_state.refresh_token[0] != '\0' &&
        (g_auth_state.token_expires_at <= 0 ||
         (g_auth_state.token_expires_at - current_time_seconds()) < 60)) {
        *out_needs_refresh = true;
        return 1;  // Caller should refresh
    }

    tl_valid_token = g_auth_state.access_token;
    *out_token = tl_valid_token.c_str();
    return 0;
}

rac_result_t rac_auth_clear(void) {
    std::lock_guard<std::mutex> lock(g_auth_mutex);

    // Clear in-memory state
    reset_auth_state_locked();

    return delete_stored_auth_locked();
}

// =============================================================================
// Persistence
// =============================================================================

int rac_auth_load_stored_tokens(void) {
    std::lock_guard<std::mutex> lock(g_auth_mutex);

    if (!g_storage_available) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    char* loaded_access_token = nullptr;
    char* loaded_refresh_token = nullptr;
    char* loaded_device_id = nullptr;
    char* loaded_user_id = nullptr;
    char* loaded_organization_id = nullptr;

    const auto free_loaded = [&]() {
        free(loaded_access_token);
        free(loaded_refresh_token);
        free(loaded_device_id);
        free(loaded_user_id);
        free(loaded_organization_id);
    };

    const auto retrieve = [&](const char* key, bool required, char** out_value) -> int {
        char buffer[2048] = {};
        const int result = g_storage.retrieve(key, buffer, sizeof(buffer), g_storage.context);

        if (result > 0) {
            if (static_cast<size_t>(result) >= sizeof(buffer)) {
                memset(buffer, 0, sizeof(buffer));
                return RAC_ERROR_BUFFER_TOO_SMALL;
            }
            if (buffer[0] == '\0') {
                memset(buffer, 0, sizeof(buffer));
                return RAC_ERROR_SECURE_STORAGE_FAILED;
            }

            *out_value = rac_strdup(buffer);
            memset(buffer, 0, sizeof(buffer));
            return *out_value != nullptr ? RAC_SUCCESS : RAC_ERROR_OUT_OF_MEMORY;
        }

        memset(buffer, 0, sizeof(buffer));
        if (result == RAC_ERROR_FILE_NOT_FOUND) {
            return required ? RAC_ERROR_FILE_NOT_FOUND : RAC_SUCCESS;
        }
        if (result == 0) {
            return RAC_ERROR_SECURE_STORAGE_FAILED;
        }
        return result;
    };

    int result = retrieve(RAC_KEY_ACCESS_TOKEN, true, &loaded_access_token);
    if (result == RAC_SUCCESS) {
        result = retrieve(RAC_KEY_REFRESH_TOKEN, false, &loaded_refresh_token);
    }
    if (result == RAC_SUCCESS) {
        result = retrieve(RAC_KEY_DEVICE_ID, false, &loaded_device_id);
    }
    if (result == RAC_SUCCESS) {
        result = retrieve(RAC_KEY_USER_ID, false, &loaded_user_id);
    }
    if (result == RAC_SUCCESS) {
        result = retrieve(RAC_KEY_ORGANIZATION_ID, false, &loaded_organization_id);
    }
    if (result != RAC_SUCCESS) {
        free_loaded();
        return result;
    }

    // Commit only after every read succeeds or cleanly misses. A transient
    // failure on one optional item must not replace an already-valid in-memory
    // auth state with a partially restored one.
    free_auth_state_strings_locked();
    g_auth_state.access_token = loaded_access_token;
    g_auth_state.refresh_token = loaded_refresh_token;
    g_auth_state.device_id = loaded_device_id;
    g_auth_state.user_id = loaded_user_id;
    g_auth_state.organization_id = loaded_organization_id;
    g_auth_state.is_authenticated = true;
    // Token expiry is unknown when loading, so it will trigger refresh on first use.
    g_auth_state.token_expires_at = 0;

    return RAC_SUCCESS;
}

int rac_auth_save_tokens(void) {
    std::lock_guard<std::mutex> lock(g_auth_mutex);
    return save_tokens_locked();
}
