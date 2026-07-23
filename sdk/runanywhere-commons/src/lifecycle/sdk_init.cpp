/**
 * @file sdk_init.cpp
 * @brief Canonical two-phase SDK initialization C ABI.
 *
 * Implementation of rac_sdk_init.h. The bodies are deliberately thin: they
 * delegate to existing internal subsystems (rac_state, rac_auth_*,
 * rac_device_manager_*, rac_model_assignment_*). The platform SDK still owns
 * its concurrency primitive (Task.detached / Mutex / Future) and any
 * MainActor-isolated platform-plugin registration; this file owns the
 * deterministic, linear C call sequence that today is duplicated in five SDK
 * languages.
 *
 * Still platform-owned:
 *   - Platform-plugin (MainActor / Android Context / JS runtime) registration.
 *     Commons cannot call UIKit/AppKit, Android framework APIs, Nitro, Dart
 *     plugin channels, or browser OPFS directly; SDKs register those adapters
 *     before Phase 2.
 *   - Native transport implementations. Phase 2 sends HTTP through the
 *     registered rac_http_transport_t adapter; the underlying URLSession,
 *     OkHttp, dart:io/foundation URLSession, RN, or browser fetch code remains
 *     in the owning SDK.
 */

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "rac/core/rac_benchmark.h"  // rac_monotonic_now_ms
#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_sdk_state.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/device/rac_device_manager.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/http/rac_http_transport.h"
#include "rac/infrastructure/model_management/rac_model_assignment.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/network/rac_auth_manager.h"
#include "rac/infrastructure/network/rac_dev_config.h"
#include "rac/infrastructure/network/rac_endpoints.h"
#include "rac/infrastructure/network/rac_environment.h"
#include "rac/lifecycle/rac_sdk_init.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "errors.pb.h"
#include "model_types.pb.h"
#include "sdk_init.pb.h"
#endif

namespace {

#if defined(RAC_HAVE_PROTOBUF)

using ::runanywhere::v1::SdkInitEnvironment;
using ::runanywhere::v1::SdkInitPhase1Request;
using ::runanywhere::v1::SdkInitPhase2Request;
using ::runanywhere::v1::SdkInitResult;

// -- helpers ----------------------------------------------------------------

rac_environment_t to_rac_environment(SdkInitEnvironment env) {
    // DEVELOPMENT=0, PRODUCTION=2. Reserved former-staging (=1) → production.
    return rac_env_normalize(static_cast<rac_environment_t>(static_cast<int>(env)));
}

rac_result_t serialize_result(const SdkInitResult& result, rac_proto_buffer_t* out) {
    const size_t size = result.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 && !result.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        rac_proto_buffer_set_error(out, RAC_ERROR_EVENT_PUBLISH_FAILED,
                                   "Failed to serialize SdkInitResult");
        return RAC_ERROR_EVENT_PUBLISH_FAILED;
    }
    return rac_proto_buffer_copy(bytes.data(), size, out);
}

// Populate result.error with the canonical SDKError shape so SDK error
// converters can round-trip the failure cleanly. Mirrors what every SDK does
// today by hand in its Phase 1 catch block.
void set_error_from_code(SdkInitResult* result, rac_result_t code, const char* fallback_message) {
    auto* err = result->mutable_error();
    const int32_t signed_code = static_cast<int32_t>(code);
    const int32_t abs_code = signed_code < 0 ? -signed_code : signed_code;
    err->set_code(static_cast<::runanywhere::v1::ErrorCode>(abs_code));
    if (signed_code != 0) {
        err->set_c_abi_code(signed_code);
    }
    const char* msg = rac_error_message(code);
    err->set_message((msg && *msg != '\0') ? msg : (fallback_message ? fallback_message : ""));
    err->set_severity(::runanywhere::v1::ERROR_SEVERITY_ERROR);
    err->set_category(::runanywhere::v1::ERROR_CATEGORY_CONFIGURATION);
    err->set_timestamp_ms(rac_monotonic_now_ms());
}

bool environment_requires_external_config(rac_environment_t env) {
    return rac_env_requires_auth(env);
}

bool http_setup_applicable_for_state() {
    const rac_environment_t env = rac_state_get_environment();
    const char* api_key = rac_state_get_api_key();
    const char* base_url = rac_state_get_base_url();
    // Every environment reaches the backend through a usable base URL — there is
    // no direct-to-datastore path anymore.
    if (!rac_dev_config_is_usable_http_url(base_url)) {
        return false;
    }
    // Keyless development is a valid HTTP setup: unauthenticated PUBLIC-org
    // ingestion. Auth-required environments need a usable API key.
    return rac_dev_config_is_usable_credential(api_key) || !rac_env_auth_expected(env, api_key);
}

std::string warning_from_code(const char* prefix, rac_result_t code) {
    const char* message = rac_error_message(code);
    std::string warning = prefix != nullptr ? prefix : "operation failed";
    warning += ": ";
    warning += (message != nullptr && message[0] != '\0') ? message : "unknown error";
    return warning;
}

void append_warning(SdkInitResult* result, const std::string& warning) {
    if (result == nullptr || warning.empty()) {
        return;
    }
    if (result->warning().empty()) {
        result->set_warning(warning);
        return;
    }
    result->set_warning(result->warning() + "; " + warning);
}

bool has_nonempty_string(const char* value) {
    return value != nullptr && value[0] != '\0';
}

rac_sdk_config_t current_sdk_config_or_state(rac_environment_t env) {
    const rac_sdk_config_t* stored = rac_sdk_get_config();
    rac_sdk_config_t config = {};
    config.environment = env;
    config.api_key = rac_state_get_api_key();
    config.base_url = rac_state_get_base_url();
    config.device_id = rac_state_get_device_id();
    config.platform =
        (stored != nullptr && has_nonempty_string(stored->platform)) ? stored->platform : "unknown";
    config.sdk_version = (stored != nullptr && has_nonempty_string(stored->sdk_version))
                             ? stored->sdk_version
                             : rac_sdk_get_version();
    return config;
}

std::vector<rac_http_header_kv_t> control_plane_headers(const rac_sdk_config_t& config) {
    const rac_http_header_kv_t* defaults = nullptr;
    size_t default_count = 0;
    std::vector<rac_http_header_kv_t> headers;
    if (rac_http_default_headers(&defaults, &default_count) == RAC_SUCCESS && defaults != nullptr) {
        headers.reserve(default_count + 2);
        for (size_t i = 0; i < default_count; ++i) {
            headers.push_back(defaults[i]);
        }
    }
    if (has_nonempty_string(config.platform)) {
        headers.push_back({"X-Platform", config.platform});
    }
    if (has_nonempty_string(config.api_key)) {
        headers.push_back({"apikey", config.api_key});
    }
    return headers;
}

rac_result_t post_auth_json(rac_environment_t env, const char* endpoint, const char* request_json,
                            rac_result_t (*response_handler)(const char*)) {
    if (!has_nonempty_string(endpoint) || !has_nonempty_string(request_json) ||
        response_handler == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const char* base_url = rac_state_get_base_url();
    if (!has_nonempty_string(base_url)) {
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    if (rac_http_transport_is_registered() != RAC_TRUE) {
        return RAC_ERROR_FEATURE_NOT_AVAILABLE;
    }

    char url[2048] = {};
    if (rac_build_url(base_url, endpoint, url, sizeof(url)) < 0) {
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    rac_sdk_config_t config = current_sdk_config_or_state(env);
    std::vector<rac_http_header_kv_t> headers = control_plane_headers(config);

    rac_http_client_t* client = nullptr;
    rac_result_t rc = rac_http_client_create(&client);
    if (rc != RAC_SUCCESS) {
        return rc;
    }

    rac_http_response_t response = {};
    const size_t request_len = std::strlen(request_json);
    rac_http_request_t request = {};
    request.method = "POST";
    request.url = url;
    request.headers = headers.empty() ? nullptr : headers.data();
    request.header_count = headers.size();
    request.body_bytes = reinterpret_cast<const uint8_t*>(request_json);
    request.body_len = request_len;
    request.timeout_ms = rac_env_default_http_timeout_ms(env);
    // Auth/refresh requests carry API credentials and may carry refresh
    // tokens in the JSON body. Never replay either across a redirect.
    request.follow_redirects = RAC_FALSE;

    rc = rac_http_request_send(client, &request, &response);
    rac_http_client_destroy(client);

    if (rc != RAC_SUCCESS) {
        rac_http_response_free(&response);
        return rc;
    }

    if (response.status < 200 || response.status >= 300) {
        rac_http_response_free(&response);
        return RAC_ERROR_HTTP_ERROR;
    }

    if (response.body_bytes == nullptr || response.body_len == 0) {
        rac_http_response_free(&response);
        return RAC_ERROR_INVALID_RESPONSE;
    }

    std::string body(reinterpret_cast<const char*>(response.body_bytes), response.body_len);
    rac_http_response_free(&response);

    return response_handler(body.c_str());
}

rac_result_t handle_authenticate_response_for_init(const char* json) {
    const int result = rac_auth_handle_authenticate_response(json);
    if (result == RAC_SUCCESS || result == RAC_ERROR_SECURE_STORAGE_FAILED) {
        return static_cast<rac_result_t>(result);
    }
    return RAC_ERROR_INVALID_RESPONSE;
}

rac_result_t handle_refresh_response_for_init(const char* json) {
    const int result = rac_auth_handle_refresh_response(json);
    if (result == RAC_SUCCESS || result == RAC_ERROR_SECURE_STORAGE_FAILED) {
        return static_cast<rac_result_t>(result);
    }
    return RAC_ERROR_INVALID_RESPONSE;
}

rac_result_t perform_token_refresh(SdkInitResult* result);

rac_result_t perform_authentication(SdkInitResult* result) {
    if (result == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    if (rac_auth_is_authenticated() && !rac_auth_needs_refresh()) {
        result->set_http_configured(true);
        result->set_has_completed_http_setup(true);
        return RAC_SUCCESS;
    }
    if (rac_auth_is_authenticated()) {
        const rac_result_t refresh_rc = perform_token_refresh(result);
        if (refresh_rc == RAC_SUCCESS) {
            return RAC_SUCCESS;
        }
        if (refresh_rc != RAC_ERROR_HTTP_ERROR && refresh_rc != RAC_ERROR_INVALID_RESPONSE &&
            refresh_rc != RAC_ERROR_INVALID_CONFIGURATION) {
            // Transport-level failure (offline/timeout) — keep the persisted
            // tokens so a later retry can still refresh.
            return refresh_rc;
        }
        // The backend rejected the refresh token (expired/rotated) or the
        // persisted state is unusable. Without this fallback the stale tokens
        // keep rac_auth_is_authenticated() true forever and every
        // token-requiring request 401s. Drop the state and re-authenticate
        // with the API key.
        RAC_LOG_WARNING("SDKInit",
                        "Token refresh rejected (rc=%d), clearing auth state and "
                        "re-authenticating",
                        refresh_rc);
        const rac_result_t clear_rc = rac_auth_clear();
        if (clear_rc != RAC_SUCCESS) {
            result->set_http_configured(false);
            result->set_has_completed_http_setup(false);
            return clear_rc;
        }
    }

    const rac_environment_t env = rac_state_get_environment();
    if (!environment_requires_external_config(env)) {
        result->set_http_configured(rac_http_transport_is_registered() == RAC_TRUE);
        result->set_has_completed_http_setup(true);
        return RAC_SUCCESS;
    }

    const char* api_key = rac_state_get_api_key();
    const char* base_url = rac_state_get_base_url();
    if (!has_nonempty_string(base_url)) {
        result->set_http_configured(false);
        result->set_has_completed_http_setup(false);
        return RAC_ERROR_INVALID_CONFIGURATION;
    }
    if (!rac_env_auth_expected(env, api_key)) {
        // Keyless development: requests go out unauthenticated (PUBLIC org),
        // there is no token to fetch.
        result->set_http_configured(rac_http_transport_is_registered() == RAC_TRUE);
        result->set_has_completed_http_setup(true);
        return RAC_SUCCESS;
    }
    if (!has_nonempty_string(api_key)) {
        result->set_http_configured(false);
        result->set_has_completed_http_setup(false);
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    rac_sdk_config_t config = current_sdk_config_or_state(env);
    char* request_json = rac_auth_build_authenticate_request(&config);
    if (request_json == nullptr) {
        result->set_http_configured(false);
        result->set_has_completed_http_setup(false);
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    const rac_result_t rc = post_auth_json(env, RAC_ENDPOINT_AUTHENTICATE, request_json,
                                           handle_authenticate_response_for_init);
    std::free(request_json);
    if (rc != RAC_SUCCESS) {
        result->set_http_configured(false);
        result->set_has_completed_http_setup(false);
        return rc;
    }

    result->set_http_configured(true);
    result->set_has_completed_http_setup(true);
    return RAC_SUCCESS;
}

rac_result_t perform_token_refresh(SdkInitResult* result) {
    if (result == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const rac_environment_t env = rac_state_get_environment();
    if (!environment_requires_external_config(env)) {
        result->set_http_configured(rac_http_transport_is_registered() == RAC_TRUE);
        result->set_has_completed_http_setup(true);
        return RAC_SUCCESS;
    }

    char* request_json = rac_auth_build_refresh_request();
    if (request_json == nullptr) {
        result->set_http_configured(false);
        result->set_has_completed_http_setup(false);
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    const rac_result_t rc =
        post_auth_json(env, RAC_ENDPOINT_REFRESH, request_json, handle_refresh_response_for_init);
    std::free(request_json);
    if (rc != RAC_SUCCESS) {
        result->set_http_configured(false);
        result->set_has_completed_http_setup(false);
        return rc;
    }

    result->set_http_configured(true);
    result->set_has_completed_http_setup(true);
    return RAC_SUCCESS;
}

uint32_t clamp_count_to_u32(int count) {
    return static_cast<uint32_t>(std::max(0, count));
}

rac_result_t refresh_model_registry(SdkInitResult* result, bool force_refresh, bool rescan_local) {
    if (result == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (registry == nullptr) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    ::runanywhere::v1::ModelRegistryRefreshRequest request;
    request.set_include_remote_catalog(false);
    request.set_include_downloaded_state(true);
    request.set_force_refresh(force_refresh);
    request.set_rescan_local(rescan_local);

    const size_t size = request.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 && !request.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        return RAC_ERROR_EVENT_PUBLISH_FAILED;
    }

    rac_proto_buffer_t out = {};
    const rac_result_t rc =
        rac_model_registry_refresh_proto(registry, bytes.data(), bytes.size(), &out);
    if (rc != RAC_SUCCESS) {
        rac_proto_buffer_free(&out);
        return rc;
    }

    ::runanywhere::v1::ModelRegistryRefreshResult refresh_result;
    if (out.size > 0 && !refresh_result.ParseFromArray(out.data, static_cast<int>(out.size))) {
        rac_proto_buffer_free(&out);
        return RAC_ERROR_INVALID_RESPONSE;
    }
    rac_proto_buffer_free(&out);

    result->set_linked_models_count(clamp_count_to_u32(refresh_result.discovered_count()));
    return RAC_SUCCESS;
}

rac_result_t discover_downloaded_models(SdkInitResult* result) {
    if (result == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (registry == nullptr) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    ::runanywhere::v1::ModelDiscoveryRequest request;
    request.set_recursive(true);
    request.set_link_downloaded(true);
    request.set_include_built_in(false);
    request.set_include_user_imports(true);

    const size_t size = request.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 && !request.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        return RAC_ERROR_EVENT_PUBLISH_FAILED;
    }

    rac_proto_buffer_t out = {};
    const rac_result_t rc =
        rac_model_registry_discover_proto(registry, bytes.data(), bytes.size(), &out);
    if (rc != RAC_SUCCESS) {
        rac_proto_buffer_free(&out);
        return rc;
    }

    ::runanywhere::v1::ModelDiscoveryResult discovery_result;
    if (out.size > 0 && !discovery_result.ParseFromArray(out.data, static_cast<int>(out.size))) {
        rac_proto_buffer_free(&out);
        return RAC_ERROR_INVALID_RESPONSE;
    }
    rac_proto_buffer_free(&out);

    result->set_linked_models_count(clamp_count_to_u32(discovery_result.linked_count()));
    result->set_discovered_orphans(0);
    return RAC_SUCCESS;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

extern "C" {

#if defined(RAC_HAVE_PROTOBUF)
namespace {

/**
 * Phase-1 failure: publish the lifecycle FAILED event (the single source of
 * INITIALIZATION_STAGE_* emits — platform SDKs no longer hand-emit
 * duplicates) and serialize the failed SdkInitResult.
 */
rac_result_t phase1_failure(rac_result_t code, const char* message, int64_t start_ms,
                            rac_proto_buffer_t* out_result) {
    rac::events::publish_initialization_failed(code, message);
    SdkInitResult result;
    result.set_phase(::runanywhere::v1::SDK_INIT_PHASE_ONE);
    result.set_success(false);
    set_error_from_code(&result, code, message);
    result.set_duration_ms(rac_monotonic_now_ms() - start_ms);
    return serialize_result(result, out_result);
}

}  // namespace
#endif  // RAC_HAVE_PROTOBUF

rac_result_t rac_sdk_init_phase1_proto(const uint8_t* in_request_bytes, size_t in_size,
                                       rac_proto_buffer_t* out_RASdkInitResult) {
    if (!out_RASdkInitResult) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

#if !defined(RAC_HAVE_PROTOBUF)
    rac_proto_buffer_set_error(out_RASdkInitResult, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                               "rac_sdk_init_phase1_proto requires RAC_HAVE_PROTOBUF");
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    const int64_t start_ms = rac_monotonic_now_ms();

    // Single source of SDK lifecycle events: STARTED at entry (before
    // validation, matching Swift's old hand-emit timing), FAILED on every
    // failure path, COMPLETED + duration_ms on success.
    rac::events::publish_initialization_started();

    const rac_result_t validate = rac_proto_bytes_validate(in_request_bytes, in_size);
    if (validate != RAC_SUCCESS) {
        return phase1_failure(validate, "Invalid SdkInitPhase1Request bytes", start_ms,
                              out_RASdkInitResult);
    }

    SdkInitPhase1Request request;
    if (in_size > 0) {
        const void* data = rac_proto_bytes_data_or_empty(in_request_bytes, in_size);
        if (!request.ParseFromArray(data, static_cast<int>(in_size))) {
            return phase1_failure(RAC_ERROR_INVALID_ARGUMENT,
                                  "Failed to parse SdkInitPhase1Request", start_ms,
                                  out_RASdkInitResult);
        }
    }

    const rac_environment_t env = to_rac_environment(request.environment());
    std::string api_key = request.api_key();
    std::string base_url = request.base_url();
    const std::string device_id = request.device_id();

    // Development (keyless OSS): fill baked staging backend URL when empty.
    // Staging no longer wipes keys — it is a deprecated production alias.
    if (env == RAC_ENV_DEVELOPMENT && base_url.empty()) {
        const char* baked = rac_dev_config_get_staging_base_url();
        if (rac_dev_config_is_usable_http_url(baked)) {
            base_url = baked;
        }
    }
    const std::string platform = request.platform();
    const std::string sdk_version =
        request.sdk_version().empty() ? std::string(rac_sdk_get_version()) : request.sdk_version();

    // Step 1: Validate inputs. Staging/production require API key + URL.
    // Development validates optionally (baked URL / keyless).
    if (environment_requires_external_config(env) || env == RAC_ENV_DEVELOPMENT) {
        const rac_validation_result_t key_check =
            rac_validate_api_key(api_key.empty() ? nullptr : api_key.c_str(), env);
        if (key_check != RAC_VALIDATION_OK) {
            return phase1_failure(RAC_ERROR_INVALID_ARGUMENT,
                                  rac_validation_error_message(key_check), start_ms,
                                  out_RASdkInitResult);
        }
        const rac_validation_result_t url_check =
            rac_validate_base_url(base_url.empty() ? nullptr : base_url.c_str(), env);
        if (url_check != RAC_VALIDATION_OK) {
            return phase1_failure(RAC_ERROR_INVALID_ARGUMENT,
                                  rac_validation_error_message(url_check), start_ms,
                                  out_RASdkInitResult);
        }
    }

    // Step 2: Initialize SDK state (environment + cached api_key + base_url +
    // device_id). After this returns, rac_state_is_initialized() == true and
    // every other commons subsystem can read these values without a vtable
    // round-trip. Mirrors RunAnywhere.swift Phase 1 step 3 + 4.5. Persistence
    // of api_key/base_url to Keychain/Keystore stays on the platform side
    // (Swift's KeychainManager.storeSDKParams) because OS storage policies
    // (kSecAttrAccessible* on Apple, Android Keystore-backed storage on Android)
    // are platform-specific.
    const rac_result_t state_rc = rac_state_initialize(env, api_key.empty() ? "" : api_key.c_str(),
                                                       base_url.empty() ? "" : base_url.c_str(),
                                                       device_id.empty() ? "" : device_id.c_str());
    if (state_rc != RAC_SUCCESS) {
        return phase1_failure(state_rc, "rac_state_initialize failed", start_ms,
                              out_RASdkInitResult);
    }

    rac_sdk_config_t sdk_config = {};
    sdk_config.environment = env;
    sdk_config.api_key = api_key.empty() ? "" : api_key.c_str();
    sdk_config.base_url = base_url.empty() ? "" : base_url.c_str();
    sdk_config.device_id = device_id.empty() ? "" : device_id.c_str();
    sdk_config.platform = platform.empty() ? "unknown" : platform.c_str();
    sdk_config.sdk_version = sdk_version.c_str();

    const rac_validation_result_t sdk_config_rc = rac_sdk_init(&sdk_config);
    if (sdk_config_rc != RAC_VALIDATION_OK) {
        return phase1_failure(RAC_ERROR_INVALID_CONFIGURATION,
                              rac_validation_error_message(sdk_config_rc), start_ms,
                              out_RASdkInitResult);
    }

    // Phase 1 complete.
    const int64_t duration_ms = rac_monotonic_now_ms() - start_ms;
    rac::events::publish_initialization_completed(duration_ms);
    SdkInitResult result;
    result.set_phase(::runanywhere::v1::SDK_INIT_PHASE_ONE);
    result.set_success(true);
    result.set_duration_ms(duration_ms);
    return serialize_result(result, out_RASdkInitResult);
#endif  // RAC_HAVE_PROTOBUF
}

rac_result_t rac_sdk_init_phase2_proto(const uint8_t* in_request_bytes, size_t in_size,
                                       rac_proto_buffer_t* out_RASdkInitResult) {
    if (!out_RASdkInitResult) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

#if !defined(RAC_HAVE_PROTOBUF)
    rac_proto_buffer_set_error(out_RASdkInitResult, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                               "rac_sdk_init_phase2_proto requires RAC_HAVE_PROTOBUF");
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    const int64_t start_ms = rac_monotonic_now_ms();

    const rac_result_t validate = rac_proto_bytes_validate(in_request_bytes, in_size);
    if (validate != RAC_SUCCESS) {
        SdkInitResult result;
        result.set_phase(::runanywhere::v1::SDK_INIT_PHASE_TWO);
        result.set_success(false);
        set_error_from_code(&result, validate, "Invalid SdkInitPhase2Request bytes");
        result.set_duration_ms(rac_monotonic_now_ms() - start_ms);
        return serialize_result(result, out_RASdkInitResult);
    }

    SdkInitPhase2Request request;
    if (in_size > 0) {
        const void* data = rac_proto_bytes_data_or_empty(in_request_bytes, in_size);
        if (!request.ParseFromArray(data, static_cast<int>(in_size))) {
            SdkInitResult result;
            result.set_phase(::runanywhere::v1::SDK_INIT_PHASE_TWO);
            result.set_success(false);
            set_error_from_code(&result, RAC_ERROR_INVALID_ARGUMENT,
                                "Failed to parse SdkInitPhase2Request");
            result.set_duration_ms(rac_monotonic_now_ms() - start_ms);
            return serialize_result(result, out_RASdkInitResult);
        }
    }

    if (!rac_state_is_initialized()) {
        SdkInitResult result;
        result.set_phase(::runanywhere::v1::SDK_INIT_PHASE_TWO);
        result.set_success(false);
        set_error_from_code(&result, RAC_ERROR_NOT_INITIALIZED,
                            "Phase 1 must complete before Phase 2");
        result.set_duration_ms(rac_monotonic_now_ms() - start_ms);
        return serialize_result(result, out_RASdkInitResult);
    }

    SdkInitResult result;
    result.set_phase(::runanywhere::v1::SDK_INIT_PHASE_TWO);
    const bool http_applicable = http_setup_applicable_for_state();
    result.set_http_applicable(http_applicable);

    // Step 1: Authenticate through the registered platform HTTP transport.
    // Development mode does not require auth; staging/production require
    // api_key/base_url from Phase 1. Failures stay non-fatal so cached/local
    // models remain available while offline.
    if (http_applicable) {
        const rac_result_t auth_rc = perform_authentication(&result);
        if (auth_rc != RAC_SUCCESS) {
            append_warning(&result, warning_from_code("auth setup deferred", auth_rc));
        }

        // Step 2: Register device + fetch assignments only on the JWT path.
        // Keyless development posts PUBLIC-org telemetry without register/for-sdk.
        const rac_environment_t env = rac_state_get_environment();
        const char* api_key = rac_state_get_api_key();
        if (rac_env_auth_expected(env, api_key)) {
            const char* build_token =
                request.build_token().empty() ? nullptr : request.build_token().c_str();
            const rac_result_t dev_rc = rac_device_manager_register_if_needed(env, build_token);
            const bool device_registered =
                (dev_rc == RAC_SUCCESS) || (rac_device_manager_is_registered() == RAC_TRUE);
            result.set_device_registered(device_registered);
            if (dev_rc != RAC_SUCCESS && dev_rc != RAC_ERROR_FEATURE_NOT_AVAILABLE &&
                dev_rc != RAC_ERROR_NOT_INITIALIZED) {
                // Surface as a warning rather than aborting — matches Swift's
                // "Device registration failed (non-critical)" branch.
                append_warning(&result, warning_from_code("device registration deferred", dev_rc));
            }

            // Step 3: Fetch model assignments (cached).
            rac_model_info_t** assigned_models = nullptr;
            size_t assigned_count = 0;
            const rac_result_t fetch_rc = rac_model_assignment_fetch(
                request.force_refresh_assignments() ? RAC_TRUE : RAC_FALSE, &assigned_models,
                &assigned_count);
            if (fetch_rc == RAC_SUCCESS && assigned_models != nullptr) {
                result.set_linked_models_count(static_cast<uint32_t>(assigned_count));
                rac_model_info_array_free(assigned_models, assigned_count);
            } else if (fetch_rc != RAC_ERROR_FEATURE_NOT_AVAILABLE && fetch_rc != RAC_SUCCESS) {
                append_warning(&result,
                               warning_from_code("model assignment fetch deferred", fetch_rc));
            }
        } else {
            result.set_device_registered(false);
        }
    } else {
        result.set_device_registered(rac_device_manager_is_registered() == RAC_TRUE);
    }

    // Step 4: Flush telemetry via the sink registered by the SDK.
    if (request.flush_telemetry()) {
        const rac_result_t flush_rc = rac_events_flush_telemetry_sink();
        if (flush_rc != RAC_SUCCESS && flush_rc != RAC_ERROR_FEATURE_NOT_AVAILABLE) {
            append_warning(&result, warning_from_code("telemetry flush deferred", flush_rc));
        }
    }

    // Step 5: Reconcile registry rows with downloaded/local files when the
    // SDK asks for the startup discovery pass.
    if (request.rescan_local_models()) {
        const rac_result_t refresh_rc = refresh_model_registry(
            &result, request.force_refresh_assignments(), request.rescan_local_models());
        if (refresh_rc != RAC_SUCCESS && refresh_rc != RAC_ERROR_FEATURE_NOT_AVAILABLE) {
            append_warning(&result,
                           warning_from_code("model registry refresh deferred", refresh_rc));
        }
    }
    if (request.discover_downloaded_models()) {
        const rac_result_t discover_rc = discover_downloaded_models(&result);
        if (discover_rc != RAC_SUCCESS && discover_rc != RAC_ERROR_FEATURE_NOT_AVAILABLE) {
            append_warning(&result,
                           warning_from_code("downloaded model discovery deferred", discover_rc));
        }
    }

    // Phase 2 succeeds in offline mode too — Swift mirrors this policy.
    result.set_success(true);
    result.set_duration_ms(rac_monotonic_now_ms() - start_ms);
    return serialize_result(result, out_RASdkInitResult);
#endif  // RAC_HAVE_PROTOBUF
}

rac_result_t rac_sdk_retry_http_proto(rac_proto_buffer_t* out_RASdkInitResult) {
    if (!out_RASdkInitResult) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

#if !defined(RAC_HAVE_PROTOBUF)
    rac_proto_buffer_set_error(out_RASdkInitResult, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                               "rac_sdk_retry_http_proto requires RAC_HAVE_PROTOBUF");
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    const int64_t start_ms = rac_monotonic_now_ms();

    SdkInitResult result;
    result.set_phase(::runanywhere::v1::SDK_INIT_PHASE_RETRY_HTTP);

    if (!rac_state_is_initialized()) {
        result.set_success(false);
        set_error_from_code(&result, RAC_ERROR_NOT_INITIALIZED,
                            "Phase 1 must complete before retry");
        result.set_duration_ms(rac_monotonic_now_ms() - start_ms);
        return serialize_result(result, out_RASdkInitResult);
    }
    result.set_http_applicable(http_setup_applicable_for_state());

    // Idempotent fast path: authenticated and token is still valid.
    if (rac_auth_is_authenticated() && !rac_auth_needs_refresh()) {
        result.set_success(true);
        result.set_http_configured(true);
        result.set_has_completed_http_setup(true);
        result.set_warning("already authenticated");
        result.set_duration_ms(rac_monotonic_now_ms() - start_ms);
        return serialize_result(result, out_RASdkInitResult);
    }

    // perform_authentication() handles the refreshed/stale/unauthenticated
    // cases itself, including the rejected-refresh → clear + full re-auth
    // fallback — so the retry path must not short-circuit into a bare refresh.
    const rac_result_t auth_rc = perform_authentication(&result);
    result.set_success(true);
    if (auth_rc != RAC_SUCCESS) {
        append_warning(&result, warning_from_code("auth retry deferred", auth_rc));
    } else if (!result.http_configured() && result.warning().empty()) {
        append_warning(&result, "no usable external config");
    }
    result.set_duration_ms(rac_monotonic_now_ms() - start_ms);
    return serialize_result(result, out_RASdkInitResult);
#endif  // RAC_HAVE_PROTOBUF
}

}  // extern "C"
