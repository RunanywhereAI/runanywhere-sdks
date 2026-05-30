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
 * Deferred (kept in the platform SDK for now):
 *   - HTTP authentication round-trip. Swift builds the JSON via
 *     rac_auth_build_authenticate_request(), POSTs it through URLSession,
 *     and hands the response to rac_auth_handle_authenticate_response(). The
 *     wire format and state updates are already in commons; only the
 *     orchestration loop is duplicated. Folding this into Phase 2 collides
 *     with concurrent agents touching download_orchestrator and
 *     model_registry, so it stays in the SDK for now.
 *   - Platform-plugin (MainActor) registration. CppBridge.initializeServices
 *     is invoked by Swift after Phase 1 returns because Apple's UIKit/AppKit
 *     APIs require the main run loop. Commons cannot drive those callbacks
 *     itself.
 *   - Telemetry flush. There is no global rac_telemetry_manager_t accessor
 *     yet — managers are created per-SDK via rac_telemetry_manager_create.
 *     Phase 2 surfaces a flushed-success bit so SDKs can choose to call
 *     rac_telemetry_manager_flush themselves once they have a handle.
 *   - Model discovery. rac_model_registry_discover_proto requires a registry
 *     handle the SDK already owns; passing that handle through Phase 2
 *     would couple this surface to the in-flight registry refactor.
 *
 * Each deferred step is reflected on the SdkInitResult envelope so the SDK
 * can decide whether to invoke the corresponding follow-up entry point
 * (rac_sdk_retry_http_proto, the existing rac_telemetry_manager_flush, or
 * rac_model_registry_discover_proto on its own handle).
 */

#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#include "rac/core/rac_benchmark.h"  // rac_monotonic_now_ms
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_sdk_state.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/device/rac_device_manager.h"
#include "rac/infrastructure/model_management/rac_model_assignment.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/network/rac_auth_manager.h"
#include "rac/infrastructure/network/rac_environment.h"
#include "rac/lifecycle/rac_sdk_init.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "errors.pb.h"
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
    switch (env) {
        case ::runanywhere::v1::SDK_INIT_ENVIRONMENT_STAGING:
            return RAC_ENV_STAGING;
        case ::runanywhere::v1::SDK_INIT_ENVIRONMENT_PRODUCTION:
            return RAC_ENV_PRODUCTION;
        case ::runanywhere::v1::SDK_INIT_ENVIRONMENT_DEVELOPMENT:
        default:
            return RAC_ENV_DEVELOPMENT;
    }
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

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

extern "C" {

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

    const rac_result_t validate = rac_proto_bytes_validate(in_request_bytes, in_size);
    if (validate != RAC_SUCCESS) {
        SdkInitResult result;
        result.set_phase(::runanywhere::v1::SDK_INIT_PHASE_ONE);
        result.set_success(false);
        set_error_from_code(&result, validate, "Invalid SdkInitPhase1Request bytes");
        result.set_duration_ms(rac_monotonic_now_ms() - start_ms);
        return serialize_result(result, out_RASdkInitResult);
    }

    SdkInitPhase1Request request;
    if (in_size > 0) {
        const void* data = rac_proto_bytes_data_or_empty(in_request_bytes, in_size);
        if (!request.ParseFromArray(data, static_cast<int>(in_size))) {
            SdkInitResult result;
            result.set_phase(::runanywhere::v1::SDK_INIT_PHASE_ONE);
            result.set_success(false);
            set_error_from_code(&result, RAC_ERROR_INVALID_ARGUMENT,
                                "Failed to parse SdkInitPhase1Request");
            result.set_duration_ms(rac_monotonic_now_ms() - start_ms);
            return serialize_result(result, out_RASdkInitResult);
        }
    }

    const rac_environment_t env = to_rac_environment(request.environment());
    const std::string api_key = request.api_key();
    const std::string base_url = request.base_url();
    const std::string device_id = request.device_id();

    // Step 1: Validate inputs. Staging/production require API key + URL.
    if (environment_requires_external_config(env)) {
        const rac_validation_result_t key_check =
            rac_validate_api_key(api_key.empty() ? nullptr : api_key.c_str(), env);
        if (key_check != RAC_VALIDATION_OK) {
            SdkInitResult result;
            result.set_phase(::runanywhere::v1::SDK_INIT_PHASE_ONE);
            result.set_success(false);
            set_error_from_code(&result, RAC_ERROR_INVALID_ARGUMENT,
                                rac_validation_error_message(key_check));
            result.set_duration_ms(rac_monotonic_now_ms() - start_ms);
            return serialize_result(result, out_RASdkInitResult);
        }
        const rac_validation_result_t url_check =
            rac_validate_base_url(base_url.empty() ? nullptr : base_url.c_str(), env);
        if (url_check != RAC_VALIDATION_OK) {
            SdkInitResult result;
            result.set_phase(::runanywhere::v1::SDK_INIT_PHASE_ONE);
            result.set_success(false);
            set_error_from_code(&result, RAC_ERROR_INVALID_ARGUMENT,
                                rac_validation_error_message(url_check));
            result.set_duration_ms(rac_monotonic_now_ms() - start_ms);
            return serialize_result(result, out_RASdkInitResult);
        }
    }

    // Step 2: Initialize SDK state (environment + cached api_key + base_url +
    // device_id). After this returns, rac_state_is_initialized() == true and
    // every other commons subsystem can read these values without a vtable
    // round-trip. Mirrors RunAnywhere.swift Phase 1 step 3 + 4.5. Persistence
    // of api_key/base_url to Keychain/Keystore stays on the platform side
    // (Swift's KeychainManager.storeSDKParams) because OS storage policies
    // (kSecAttrAccessible* on Apple, EncryptedSharedPreferences on Android)
    // are platform-specific.
    const rac_result_t state_rc = rac_state_initialize(env, api_key.empty() ? "" : api_key.c_str(),
                                                       base_url.empty() ? "" : base_url.c_str(),
                                                       device_id.empty() ? "" : device_id.c_str());
    if (state_rc != RAC_SUCCESS) {
        SdkInitResult result;
        result.set_phase(::runanywhere::v1::SDK_INIT_PHASE_ONE);
        result.set_success(false);
        set_error_from_code(&result, state_rc, "rac_state_initialize failed");
        result.set_duration_ms(rac_monotonic_now_ms() - start_ms);
        return serialize_result(result, out_RASdkInitResult);
    }

    // Phase 1 complete.
    SdkInitResult result;
    result.set_phase(::runanywhere::v1::SDK_INIT_PHASE_ONE);
    result.set_success(true);
    result.set_duration_ms(rac_monotonic_now_ms() - start_ms);
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
    (void)request;  // Reserved for future hints.

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

    // Step 1: Snapshot HTTP/auth state. The actual HTTP authentication
    // round-trip stays in the platform SDK today (see file header notes).
    // We surface the current state so the SDK can choose to invoke
    // rac_sdk_retry_http_proto() if needed.
    result.set_http_configured(rac_auth_is_authenticated());

    // Step 2: Register device with backend if callbacks are wired and the
    // current environment requires it. Failures are non-fatal — Swift logs a
    // warning and continues so local/cached models stay accessible.
    const rac_environment_t env = rac_state_get_environment();
    const rac_result_t dev_rc = rac_device_manager_register_if_needed(env, /*build_token=*/nullptr);
    const bool device_registered =
        (dev_rc == RAC_SUCCESS) || (rac_device_manager_is_registered() == RAC_TRUE);
    result.set_device_registered(device_registered);
    if (dev_rc != RAC_SUCCESS && dev_rc != RAC_ERROR_FEATURE_NOT_AVAILABLE) {
        // Surface as a warning rather than aborting — matches Swift's
        // "Device registration failed (non-critical)" branch.
        const char* msg = rac_error_message(dev_rc);
        result.set_warning(std::string("device registration deferred: ") +
                           ((msg && *msg != '\0') ? msg : "unknown error"));
    }

    // Step 3: Fetch model assignments (cached). When callbacks are not wired
    // this returns RAC_ERROR_FEATURE_NOT_AVAILABLE; we treat that as offline.
    rac_model_info_t** assigned_models = nullptr;
    size_t assigned_count = 0;
    const rac_result_t fetch_rc =
        rac_model_assignment_fetch(/*force_refresh=*/RAC_FALSE, &assigned_models, &assigned_count);
    if (fetch_rc == RAC_SUCCESS && assigned_models != nullptr) {
        result.set_linked_models_count(static_cast<uint32_t>(assigned_count));
        rac_model_info_array_free(assigned_models, assigned_count);
    } else if (fetch_rc != RAC_ERROR_FEATURE_NOT_AVAILABLE && fetch_rc != RAC_SUCCESS) {
        // Non-fatal: cache may be empty and HTTP unavailable. Warning surface
        // mirrors Swift's offline-mode branch.
        if (result.warning().empty()) {
            const char* msg = rac_error_message(fetch_rc);
            result.set_warning(std::string("model assignment fetch deferred: ") +
                               ((msg && *msg != '\0') ? msg : "unknown error"));
        }
    }

    // Telemetry flush + model discovery are deferred to platform SDKs (see
    // file header). Both have existing public ABIs (rac_telemetry_manager_*,
    // rac_model_registry_discover_proto) that the SDK can call directly with
    // the handles it already owns.

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

    // Idempotent fast path: already authenticated.
    if (rac_auth_is_authenticated()) {
        result.set_success(true);
        result.set_http_configured(true);
        result.set_warning("already authenticated");
        result.set_duration_ms(rac_monotonic_now_ms() - start_ms);
        return serialize_result(result, out_RASdkInitResult);
    }

    const rac_environment_t env = rac_state_get_environment();
    const char* cached_key = rac_state_get_api_key();
    const char* cached_url = rac_state_get_base_url();
    const bool has_external_config = environment_requires_external_config(env) &&
                                     cached_key != nullptr && *cached_key != '\0' &&
                                     cached_url != nullptr && *cached_url != '\0';

    if (!has_external_config) {
        // No retry possible — match Swift's "no usable external config" debug
        // branch. This is a successful no-op so SDKs do not surface it as an
        // error to users.
        result.set_success(true);
        result.set_http_configured(false);
        result.set_warning("no usable external config; retry skipped");
        result.set_duration_ms(rac_monotonic_now_ms() - start_ms);
        return serialize_result(result, out_RASdkInitResult);
    }

    // The actual auth round-trip lives in the platform SDK (see file header
    // notes). When that completes, rac_auth_handle_authenticate_response()
    // updates the manager state. Until then, surface a deferred warning so
    // the SDK knows to drive the round-trip itself.
    result.set_success(true);
    result.set_http_configured(false);
    result.set_warning("auth retry deferred to platform transport");
    result.set_duration_ms(rac_monotonic_now_ms() - start_ms);
    return serialize_result(result, out_RASdkInitResult);
#endif  // RAC_HAVE_PROTOBUF
}

}  // extern "C"
