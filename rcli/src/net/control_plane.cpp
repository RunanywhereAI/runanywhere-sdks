/**
 * @file control_plane.cpp
 * @brief Control-plane network wiring for rcli — see control_plane.h.
 *
 * The CLI drives the canonical commons entry points and adds only what is
 * genuinely CLI-shaped: a buffered POST helper the telemetry commands reuse and
 * the login flow's user-facing error text. Device callbacks are installed by
 * bootstrap.cpp through the ordinary rac_device_manager surface; request
 * building and response parsing stay in commons, per the repo layering rule.
 */

#include "net/control_plane.h"

#include <cstdlib>
#include <vector>

#include "rac/core/rac_sdk_state.h"
#include "rac/desktop/rac_desktop.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/network/rac_auth_manager.h"
#include "rac/infrastructure/network/rac_endpoints.h"
#include "rac/infrastructure/network/rac_environment.h"
#include "rac/lifecycle/rac_sdk_init.h"

#include "sdk_init.pb.h"

#include "io/output.h"
#include "io/proto.h"

namespace rcli::net {

namespace {

namespace v1 = runanywhere::v1;

constexpr size_t kErrorBodyPreview = 500;

std::string single_line_preview(const std::string& body) {
    std::string preview = body.substr(0, kErrorBodyPreview);
    for (char& ch : preview) {
        if (ch == '\n' || ch == '\r' || ch == '\t') {
            ch = ' ';
        }
    }
    if (body.size() > kErrorBodyPreview) {
        preview += "…";
    }
    return preview;
}

}  // namespace

const char* platform_name() {
    return rac_desktop_platform_name();
}

const std::string& device_model() {
    static const std::string model = rac_desktop_device_model();
    return model;
}

const std::string& os_version_string() {
    static const std::string version = rac_desktop_os_version();
    return version;
}

std::string HttpResult::describe() const {
    if (transport != RAC_SUCCESS) {
        std::string message = "network error: " + out::describe_result(transport);
        if (!body.empty()) {
            message += " (" + single_line_preview(body) + ")";
        }
        return message;
    }
    std::string message = "HTTP " + std::to_string(status);
    if (!body.empty()) {
        message += ": " + single_line_preview(body);
    }
    return message;
}

HttpResult control_plane_post(const std::string& endpoint, const std::string& json_body,
                              bool bearer_auth) {
    HttpResult result;

    const char* base_url = rac_state_get_base_url();
    if (base_url == nullptr || base_url[0] == '\0') {
        result.transport = RAC_ERROR_INVALID_CONFIGURATION;
        result.body = "control-plane base URL is not configured";
        return result;
    }

    char url[2048] = {};
    if (rac_build_url(base_url, endpoint.c_str(), url, sizeof(url)) < 0) {
        result.transport = RAC_ERROR_INVALID_CONFIGURATION;
        result.body = "failed to build control-plane URL";
        return result;
    }

    // Canonical control-plane header set — mirrors commons' phase-2 pattern:
    // defaults (Content-Type/Accept/X-SDK-*) + X-Platform + apikey [+ Bearer].
    const rac_http_header_kv_t* defaults = nullptr;
    size_t default_count = 0;
    std::vector<rac_http_header_kv_t> headers;
    if (rac_http_default_headers(&defaults, &default_count) == RAC_SUCCESS &&
        defaults != nullptr) {
        headers.assign(defaults, defaults + default_count);
    }
    headers.push_back({"X-Platform", platform_name()});
    const char* api_key = rac_state_get_api_key();
    if (api_key != nullptr && api_key[0] != '\0') {
        headers.push_back({"apikey", api_key});
    }
    std::string bearer;
    if (bearer_auth) {
        const char* token = rac_auth_get_access_token();
        if (token != nullptr && token[0] != '\0') {
            bearer = std::string("Bearer ") + token;
            headers.push_back({"Authorization", bearer.c_str()});
        }
    }

    rac_http_client_t* client = nullptr;
    rac_result_t rc = rac_http_client_create(&client);
    if (rc != RAC_SUCCESS) {
        result.transport = rc;
        return result;
    }

    rac_http_request_t request = {};
    request.method = "POST";
    request.url = url;
    request.headers = headers.data();
    request.header_count = headers.size();
    request.body_bytes = reinterpret_cast<const uint8_t*>(json_body.data());
    request.body_len = json_body.size();
    request.timeout_ms = rac_env_default_http_timeout_ms(rac_state_get_environment());
    // Credential-bearing control-plane requests never replay across redirects.
    request.follow_redirects = RAC_FALSE;

    rac_http_response_t response = {};
    rc = rac_http_request_send(client, &request, &response);
    rac_http_client_destroy(client);

    result.transport = rc;
    if (rc == RAC_SUCCESS) {
        result.status = response.status;
        if (response.body_bytes != nullptr && response.body_len > 0) {
            result.body.assign(reinterpret_cast<const char*>(response.body_bytes),
                               response.body_len);
        }
    }
    rac_http_response_free(&response);
    return result;
}

rac_result_t login(LoginSummary* out, std::string* error) {
    const rac_environment_t env = rac_state_get_environment();
    if (!rac_env_auth_expected(env, rac_state_get_api_key())) {
        if (error != nullptr) {
            *error =
                "keyless development has no JWT login; use --environment production "
                "with --base-url and --api-key";
        }
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    // Step 1: API key → JWT. Idempotent within a process; a valid token
    // short-circuits (phase 2 below then takes its authenticated fast path).
    if (!rac_auth_is_authenticated() || rac_auth_needs_refresh()) {
        const rac_sdk_config_t* config = rac_sdk_get_config();
        if (config == nullptr) {
            if (error != nullptr) {
                *error = "SDK configuration unavailable (bootstrap did not run?)";
            }
            return RAC_ERROR_NOT_INITIALIZED;
        }
        char* request_json = rac_auth_build_authenticate_request(config);
        if (request_json == nullptr) {
            if (error != nullptr) {
                *error = "failed to build authenticate request";
            }
            return RAC_ERROR_INVALID_CONFIGURATION;
        }
        const HttpResult response =
            control_plane_post(RAC_ENDPOINT_AUTHENTICATE, request_json, false);
        std::free(request_json);
        if (!response.ok()) {
            if (error != nullptr) {
                *error = "authentication failed: " + response.describe();
            }
            return response.transport != RAC_SUCCESS ? response.transport : RAC_ERROR_HTTP_ERROR;
        }
        const int auth_rc = rac_auth_handle_authenticate_response(response.body.c_str());
        if (auth_rc != RAC_SUCCESS && auth_rc != RAC_ERROR_SECURE_STORAGE_FAILED) {
            if (error != nullptr) {
                *error = "authentication response rejected: " + single_line_preview(response.body);
            }
            return RAC_ERROR_INVALID_RESPONSE;
        }
    }

    // Step 2: canonical phase-2 orchestration — device registration +
    // model-assignment fetch (telemetry flush / local rescans stay off; the
    // CLI runs those flows through their own commands).
    v1::SdkInitPhase2Request request;
    const std::string request_bytes = proto::serialize(request);
    rac_proto_buffer_t out_buffer;
    rac_proto_buffer_init(&out_buffer);
    const rac_result_t phase2_rc = rac_sdk_init_phase2_proto(
        request_bytes.empty() ? nullptr
                              : reinterpret_cast<const uint8_t*>(request_bytes.data()),
        request_bytes.size(), &out_buffer);
    v1::SdkInitResult result;
    std::string parse_error;
    if (!proto::parse_proto_buffer(&out_buffer, &result, &parse_error) ||
        phase2_rc != RAC_SUCCESS) {
        if (error != nullptr) {
            *error = "services init failed: " +
                     (parse_error.empty() ? out::describe_result(phase2_rc) : parse_error);
        }
        return phase2_rc != RAC_SUCCESS ? phase2_rc : RAC_ERROR_INVALID_RESPONSE;
    }
    if (!result.has_error() == false) {
        if (error != nullptr) {
            *error = "services init failed: " + result.error().message();
        }
        return RAC_ERROR_INVALID_STATE;
    }

    if (out != nullptr) {
        const char* organization_id = rac_auth_get_organization_id();
        const char* user_id = rac_auth_get_user_id();
        const char* backend_device_id = rac_auth_get_device_id();
        const char* persistent_device_id = rac_state_get_device_id();
        out->organization_id = organization_id != nullptr ? organization_id : "";
        out->user_id = user_id != nullptr ? user_id : "";
        out->backend_device_id = backend_device_id != nullptr ? backend_device_id : "";
        out->persistent_device_id = persistent_device_id != nullptr ? persistent_device_id : "";
        out->token_expires_at = rac_auth_get_token_expires_at();
        out->has_completed_http_setup = result.has_completed_http_setup();
        out->device_registered = rac_auth_get_device_registered();
        out->assignment_count = result.linked_models_count();
        out->warning = result.warning();
    }
    return RAC_SUCCESS;
}

}  // namespace rcli::net
