/**
 * @file control_plane.cpp
 * @brief Control-plane network wiring for rcli — see control_plane.h.
 *
 * The CLI supplies platform callbacks (device info + HTTP via the registered
 * curl transport) and drives the canonical commons entry points. Request
 * building (rac_auth_build_authenticate_request, device registration JSON)
 * and response parsing (rac_auth_handle_authenticate_response,
 * SdkInitResult) stay in commons per the repo layering rule.
 */

#include "net/control_plane.h"

#include <cstdlib>
#include <cstring>
#include <thread>
#include <vector>

#if defined(__APPLE__)
#include <sys/sysctl.h>
#endif
#if !defined(_WIN32)
#include <sys/utsname.h>
#include <unistd.h>
#endif

#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_sdk_state.h"
#include "rac/infrastructure/device/rac_device_manager.h"
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

std::string query_hostname() {
#if defined(_WIN32)
    const char* name = std::getenv("COMPUTERNAME");
    return name != nullptr ? name : "windows-host";
#else
    struct utsname info{};
    if (uname(&info) == 0 && info.nodename[0] != '\0') {
        return info.nodename;
    }
    return "desktop-host";
#endif
}

std::string query_device_model() {
#if defined(__APPLE__)
    char model[128] = {};
    size_t size = sizeof(model);
    if (sysctlbyname("hw.model", model, &size, nullptr, 0) == 0 && model[0] != '\0') {
        return model;
    }
    return "Mac";
#elif defined(_WIN32)
    return "Windows PC";
#else
    struct utsname info{};
    if (uname(&info) == 0 && info.machine[0] != '\0') {
        return std::string(info.sysname[0] != '\0' ? info.sysname : "Linux") + " " + info.machine;
    }
    return "Linux PC";
#endif
}

std::string query_os_version() {
#if defined(_WIN32)
    return {};
#else
    struct utsname info{};
    if (uname(&info) == 0 && info.release[0] != '\0') {
        // Backend os_version column caps at 20 chars.
        return std::string(info.release).substr(0, 20);
    }
    return {};
#endif
}

std::string query_chip_name() {
#if defined(__APPLE__)
    char brand[256] = {};
    size_t size = sizeof(brand);
    if (sysctlbyname("machdep.cpu.brand_string", brand, &size, nullptr, 0) == 0 &&
        brand[0] != '\0') {
        return brand;
    }
#endif
    return {};
}

const char* architecture_name() {
#if defined(__aarch64__) || defined(_M_ARM64)
    return "arm64";
#else
    return "x86_64";
#endif
}

// ---------------------------------------------------------------------------
// Device-manager callbacks. The device manager reads the strings we hand it
// after the callback returns (it builds the registration JSON immediately),
// so all backing storage is file-static — the CLI drives one control-plane
// flow at a time.
// ---------------------------------------------------------------------------

struct DeviceBridgeState {
    bool registered_this_process = false;
    std::string device_id;       // rac_state persistent UUID snapshot
    std::string device_name;     // hostname
    std::string response_body;   // outlives the http_post callback
    std::string response_error;  // outlives the http_post callback
};

DeviceBridgeState& device_state() {
    static DeviceBridgeState state;
    return state;
}

void device_get_info(rac_device_registration_info_t* out_info, void* /*user_data*/) {
    if (out_info == nullptr) {
        return;
    }
    DeviceBridgeState& state = device_state();
    state.device_name = query_hostname();

    *out_info = {};
    out_info->device_model = device_model().c_str();
    out_info->device_name = state.device_name.c_str();
    out_info->platform = platform_name();
    out_info->os_version = os_version_string().c_str();
    out_info->form_factor = "desktop";
    out_info->architecture = architecture_name();
    static const std::string chip = query_chip_name();
    out_info->chip_name = chip.c_str();

    rac_memory_info_t memory{};
    const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
    if (adapter != nullptr && adapter->get_memory_info != nullptr &&
        adapter->get_memory_info(&memory, adapter->user_data) == RAC_SUCCESS) {
        out_info->total_memory = static_cast<int64_t>(memory.total_bytes);
        out_info->available_memory = static_cast<int64_t>(memory.available_bytes);
    }

    out_info->has_neural_engine = RAC_FALSE;
    out_info->neural_engine_cores = 0;
#if defined(__APPLE__)
    out_info->gpu_family = "apple";
#else
    out_info->gpu_family = nullptr;
#endif
    out_info->battery_level = -1.0;  // desktop: unavailable → null on the wire
    out_info->battery_state = nullptr;
    out_info->is_low_power_mode = RAC_FALSE;
    out_info->core_count = static_cast<int32_t>(std::thread::hardware_concurrency());
    out_info->performance_cores = 0;
    out_info->efficiency_cores = 0;
    out_info->device_fingerprint = nullptr;  // commons falls back to device_id
}

const char* device_get_id(void* /*user_data*/) {
    DeviceBridgeState& state = device_state();
    const char* device_id = rac_state_get_device_id();
    state.device_id = device_id != nullptr ? device_id : "";
    return state.device_id.c_str();
}

rac_bool_t device_is_registered(void* /*user_data*/) {
    return device_state().registered_this_process ? RAC_TRUE : RAC_FALSE;
}

void device_set_registered(rac_bool_t registered, void* /*user_data*/) {
    device_state().registered_this_process = (registered == RAC_TRUE);
}

rac_result_t device_http_post(const char* endpoint, const char* json_body,
                              rac_bool_t requires_auth, rac_device_http_response_t* out_response,
                              void* /*user_data*/) {
    if (endpoint == nullptr || json_body == nullptr || out_response == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    DeviceBridgeState& state = device_state();
    const HttpResult result = control_plane_post(endpoint, json_body, requires_auth == RAC_TRUE);
    state.response_body = result.body;
    state.response_error = result.ok() ? std::string() : result.describe();

    *out_response = {};
    out_response->status_code = result.status;
    out_response->response_body = state.response_body.empty() ? nullptr
                                                              : state.response_body.c_str();
    if (result.ok()) {
        out_response->result = RAC_SUCCESS;
        return RAC_SUCCESS;
    }
    out_response->result =
        result.transport != RAC_SUCCESS ? result.transport : RAC_ERROR_HTTP_ERROR;
    out_response->error_message = state.response_error.c_str();
    return out_response->result;
}

}  // namespace

const char* platform_name() {
#if defined(__APPLE__)
    return "macos";
#elif defined(__linux__)
    return "linux";
#elif defined(_WIN32)
    return "windows";
#else
    return "desktop";
#endif
}

const std::string& device_model() {
    static const std::string model = query_device_model();
    return model;
}

const std::string& os_version_string() {
    static const std::string version = query_os_version();
    return version;
}

void register_device_callbacks() {
    rac_device_callbacks_t callbacks = {};
    callbacks.get_device_info = device_get_info;
    callbacks.get_device_id = device_get_id;
    callbacks.is_registered = device_is_registered;
    callbacks.set_registered = device_set_registered;
    callbacks.http_post = device_http_post;
    callbacks.user_data = nullptr;
    if (rac_device_manager_set_callbacks(&callbacks) != RAC_SUCCESS) {
        out::status_line("warning: device manager callbacks failed to install");
    }
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
    if (!rac_env_requires_auth(env)) {
        if (error != nullptr) {
            *error =
                "development mode (the default) has no control plane; pass "
                "--environment staging (or prod) together with --base-url and --api-key";
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
    if (!result.success()) {
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
        out->device_registered = result.device_registered();
        out->assignment_count = result.linked_models_count();
        out->warning = result.warning();
    }
    return RAC_SUCCESS;
}

}  // namespace rcli::net
