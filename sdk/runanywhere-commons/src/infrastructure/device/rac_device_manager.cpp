/**
 * @file rac_device_manager.cpp
 * @brief Device Registration Manager Implementation
 *
 * All business logic for device registration lives here.
 * Platform-specific operations are delegated to callbacks.
 */

#include "rac/infrastructure/device/rac_device_manager.h"

#include "rac_device_live_state_internal.h"

#include <cstring>
#include <mutex>
#include <string>

#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/infrastructure/network/rac_endpoints.h"
#include "rac/infrastructure/telemetry/rac_telemetry_manager.h"

// =============================================================================
// INTERNAL STATE
// =============================================================================

namespace {

// Thread-safe callback storage
struct DeviceManagerState {
    rac_device_callbacks_t callbacks = {};
    bool callbacks_set = false;
    // Set when the authenticate response reported device_registered=false —
    // the server holds only a placeholder row, so the platform-persisted
    // is_registered flag is stale and must not skip registration.
    bool server_unregistered = false;
    std::mutex mutex;
};

DeviceManagerState& get_state() {
    static DeviceManagerState state;
    return state;
}

// Logging category
static const char* LOG_CAT = "DeviceManager";

// Helper to emit device registered event (canonical proto stream; the
// destination router forwards it to telemetry).
void emit_device_registered(const char* device_id) {
    rac::events::publish_device_registered(device_id);
}

// Helper to emit device registration failed event.
void emit_device_registration_failed(rac_result_t error_code, const char* error_message) {
    rac::events::publish_device_registration_failed(error_code, error_message);
}

}  // namespace

// =============================================================================
// PUBLIC API
// =============================================================================

extern "C" {

rac_result_t rac_device_manager_set_callbacks(const rac_device_callbacks_t* callbacks) {
    if (!callbacks) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Validate required callbacks
    if (!callbacks->get_device_info || !callbacks->get_device_id || !callbacks->is_registered ||
        !callbacks->set_registered || !callbacks->http_post) {
        RAC_LOG_ERROR(LOG_CAT, "One or more required callbacks are NULL");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    state.callbacks = *callbacks;
    state.callbacks_set = true;

    RAC_LOG_INFO(LOG_CAT, "Device manager callbacks configured");
    return RAC_SUCCESS;
}

void rac_device_manager_clear_callbacks(void) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);
    state.callbacks = {};
    state.callbacks_set = false;
    RAC_LOG_INFO(LOG_CAT, "Device manager callbacks cleared");
}

void rac_device_manager_notify_server_unregistered(void) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);
    state.server_unregistered = true;
    RAC_LOG_INFO(LOG_CAT,
                 "Server reports device not registered (placeholder row) — next "
                 "registration attempt will run regardless of the persisted flag");
}

rac_result_t rac_device_manager_sample_live_state(rac_device_live_state_t* out) {
    if (!out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *out = {};
    out->battery_level = -1.0;

    auto& state = get_state();
    // try_lock: never let event tracking block behind an in-flight
    // registration HTTP round-trip; the caller keeps unknown sentinels.
    std::unique_lock<std::mutex> lock(state.mutex, std::try_to_lock);
    if (!lock.owns_lock()) {
        return RAC_ERROR_NOT_INITIALIZED;
    }
    if (!state.callbacks_set || !state.callbacks.get_device_info) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    // Platform fills a stack struct; string fields point at platform-owned
    // storage (same contract as registration) — copy what we keep before
    // releasing the lock.
    rac_device_registration_info_t info = {};
    info.battery_level = -1.0;
    state.callbacks.get_device_info(&info, state.callbacks.user_data);

    out->battery_level = info.battery_level;
    if (info.battery_state && info.battery_state[0] != '\0') {
        strncpy(out->battery_state, info.battery_state, sizeof(out->battery_state) - 1);
    }
    out->is_low_power_mode = info.is_low_power_mode;
    out->has_low_power_mode = RAC_TRUE;
    out->total_memory = info.total_memory;
    out->available_memory = info.available_memory;
    return RAC_SUCCESS;
}

rac_result_t rac_device_manager_register_if_needed(rac_environment_t env, const char* build_token) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (!state.callbacks_set) {
        // Benign during early init: the platform adapter may bind callbacks
        // after the first register-attempt (Web SDK ordering). Caller surfaces
        // a typed RAC_ERROR_NOT_INITIALIZED for retry logic.
        RAC_LOG_DEBUG(LOG_CAT, "Device manager callbacks not set yet — deferring registration");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    // Step 1: Check if already registered
    // Production behavior: Skip if already registered (performance, network efficiency)
    // Development behavior: Always update via UPSERT (track active devices, update last_seen_at)
    // Server heal: the authenticate response can report device_registered=false
    // (backend holds only a placeholder row), which overrides the stale
    // platform-persisted flag — otherwise a server-side device reset leaves an
    // "Unknown"/"SDK Device" row that production mode never upgrades.
    const bool was_registered =
        state.callbacks.is_registered(state.callbacks.user_data) == RAC_TRUE &&
        !state.server_unregistered;
    if (was_registered && env != RAC_ENV_DEVELOPMENT) {
        RAC_LOG_DEBUG(LOG_CAT, "Device already registered, skipping (production mode)");
        // Skip the network round-trip, but still emit the device.registered
        // telemetry so the dashboard reflects the active device on every launch
        // (not only the first-ever registration).
        const char* registered_device_id = state.callbacks.get_device_id(state.callbacks.user_data);
        if (registered_device_id != nullptr && registered_device_id[0] != '\0') {
            emit_device_registered(registered_device_id);
        }
        return RAC_SUCCESS;
    }

    if (was_registered && env == RAC_ENV_DEVELOPMENT) {
        RAC_LOG_DEBUG(LOG_CAT,
                      "Device marked as registered, but will update via UPSERT (development mode)");
    }

    RAC_LOG_INFO(LOG_CAT, "Starting device registration%s",
                 (env == RAC_ENV_DEVELOPMENT && was_registered)
                     ? " (UPSERT will update existing records)"
                     : "");

    // Step 2: Get device ID
    const char* device_id = state.callbacks.get_device_id(state.callbacks.user_data);
    if (!device_id || strlen(device_id) == 0) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to get device ID");
        emit_device_registration_failed(RAC_ERROR_INVALID_STATE, "Failed to get device ID");
        return RAC_ERROR_INVALID_STATE;
    }
    RAC_LOG_DEBUG(LOG_CAT, "Device identifier resolved for registration");

    // Step 3: Get device info
    rac_device_registration_info_t device_info = {};
    state.callbacks.get_device_info(&device_info, state.callbacks.user_data);

    // Ensure device_id is set in info
    device_info.device_id = device_id;

    // Step 4: Build registration request
    rac_device_registration_request_t request = {};
    request.device_info = device_info;

    // Get SDK version from SDK config if available
    const rac_sdk_config_t* sdk_config = rac_sdk_get_config();
    request.sdk_version = sdk_config ? sdk_config->sdk_version : "unknown";
    request.client_info = sdk_config ? sdk_config->client_info : *rac_sdk_get_client_info();
    request.build_token = (env == RAC_ENV_DEVELOPMENT) ? build_token : nullptr;
    request.last_seen_at_ms = rac_get_current_time_ms();

    // Step 5: Serialize to JSON
    char* json_ptr = nullptr;
    size_t json_len = 0;
    rac_result_t result = rac_device_registration_to_json(&request, env, &json_ptr, &json_len);

    if (result != RAC_SUCCESS || !json_ptr) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to build registration JSON");
        emit_device_registration_failed(result, "Failed to build registration JSON");
        return result;
    }

    // Step 6: Get endpoint
    const char* endpoint = rac_endpoint_device_registration(env);
    if (!endpoint) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to get device registration endpoint");
        rac_free(json_ptr);
        emit_device_registration_failed(RAC_ERROR_INVALID_STATE, "Failed to get endpoint");
        return RAC_ERROR_INVALID_STATE;
    }
    RAC_LOG_DEBUG(LOG_CAT, "Registration endpoint: %s", endpoint);
    RAC_LOG_DEBUG(LOG_CAT, "Registration payload prepared (%zu bytes)", json_len);

    // Step 7: The register endpoint always requires the SDK bearer token.
    rac_bool_t requires_auth = RAC_TRUE;
    (void)env;

    // Step 8: Make HTTP request via callback
    rac_device_http_response_t response = {};
    result = state.callbacks.http_post(endpoint, json_ptr, requires_auth, &response,
                                       state.callbacks.user_data);

    // Free JSON after use
    rac_free(json_ptr);

    // Step 9: Handle response
    if (result != RAC_SUCCESS || response.result != RAC_SUCCESS) {
        const rac_result_t response_result = result != RAC_SUCCESS ? result : response.result;
        if (response_result == RAC_ERROR_NOT_INITIALIZED) {
            // Browser callbacks start a bounded fetch on the event loop and
            // return this sentinel. The Web facade awaits it and invokes this
            // operation once more with the prepared response; do not emit a
            // false registration-failed event while that request is pending.
            RAC_LOG_DEBUG(LOG_CAT, "Device registration request pending platform completion");
            return response_result;
        }
        std::string error_msg = "Device registration failed";
        if (response.error_message) {
            error_msg = error_msg + ": " + response.error_message;
        }
        RAC_LOG_ERROR(LOG_CAT, "%s", error_msg.c_str());
        emit_device_registration_failed(result != RAC_SUCCESS ? result : response.result,
                                        response.error_message ? response.error_message
                                                               : "HTTP request failed");
        return response_result;
    }

    // Step 10: Mark as registered (server placeholder, if any, is now upgraded)
    state.callbacks.set_registered(RAC_TRUE, state.callbacks.user_data);
    state.server_unregistered = false;

    // Step 11: Emit success event
    emit_device_registered(device_id);

    RAC_LOG_INFO(LOG_CAT, "Device registration successful");
    return RAC_SUCCESS;
}

rac_bool_t rac_device_manager_is_registered(void) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (!state.callbacks_set) {
        return RAC_FALSE;
    }

    return state.callbacks.is_registered(state.callbacks.user_data);
}

void rac_device_manager_clear_registration(void) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (!state.callbacks_set) {
        return;
    }

    state.callbacks.set_registered(RAC_FALSE, state.callbacks.user_data);
    RAC_LOG_INFO(LOG_CAT, "Device registration cleared");
}

const char* rac_device_manager_get_device_id(void) {
    static thread_local std::string device_id_snapshot;

    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (!state.callbacks_set) {
        device_id_snapshot.clear();
        return nullptr;
    }

    const char* device_id = state.callbacks.get_device_id(state.callbacks.user_data);
    if (device_id == nullptr) {
        device_id_snapshot.clear();
        return nullptr;
    }

    // The callback owns its returned buffer and platform teardown may release
    // that storage as soon as this critical section ends. Snapshot it before
    // unlocking so callers never observe callback-owned memory after return.
    device_id_snapshot = device_id;
    return device_id_snapshot.c_str();
}

}  // extern "C"
