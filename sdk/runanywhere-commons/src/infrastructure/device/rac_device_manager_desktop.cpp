/**
 * @file rac_device_manager_desktop.cpp
 * @brief Desktop provider for the ordinary rac_device_manager callback surface.
 *
 * The device manager's fallback desktop provider, installed by the desktop
 * HTTP bootstrap. Hosts can replace it through the ordinary
 * rac_device_manager_set_callbacks() surface when they have richer telemetry.
 * Commons still owns the registration flow itself: it decides
 * whether registration is needed, builds the JSON, picks the endpoint, and
 * parses the response. This file only answers the four questions commons
 * cannot answer portably — what machine is this, what is its id, has it
 * registered before, and please POST this.
 *
 * The registration flag is persisted through the platform adapter's secure
 * store, matching Swift's UserDefaults flag: a device registers once, not on
 * every launch.
 */

#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

#include "rac_device_live_state_internal.h"

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#else
#include <unistd.h>

#include <sys/utsname.h>
#endif

#if defined(__APPLE__)
#include <sys/sysctl.h>
#endif

#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_sdk_state.h"
#include "desktop/desktop_internal.h"
#include "rac/desktop/rac_desktop.h"
#include "rac/infrastructure/device/rac_device_identity.h"
#include "rac/infrastructure/device/rac_device_manager.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/http/rac_http_transport.h"
#include "rac/infrastructure/network/rac_auth_manager.h"
#include "rac/infrastructure/network/rac_endpoints.h"
#include "rac/infrastructure/network/rac_environment.h"

namespace {

// Secure-store key for the "this device already registered" flag. Sits beside
// the "device_id" key rac_device_identity writes through the same adapter.
constexpr const char* kRegisteredKey = "device_registered";

// Backend os_version column caps at 20 characters.
constexpr size_t kOsVersionMax = 20;

std::string query_hostname() {
#if defined(_WIN32)
    char name[MAX_COMPUTERNAME_LENGTH + 1] = {};
    DWORD size = sizeof(name);
    if (GetComputerNameA(name, &size) && name[0] != '\0') {
        return name;
    }
    return "windows-host";
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
    // GetVersionEx reports the manifested version, not the running one, and the
    // registry read that would be accurate is not worth a wrong answer.
    return {};
#else
    struct utsname info{};
    if (uname(&info) == 0 && info.release[0] != '\0') {
        return std::string(info.release).substr(0, kOsVersionMax);
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

// Storage the callbacks hand out as const char*. The device manager holds its
// own mutex across get_device_info / get_device_id / http_post and reads the
// strings before releasing it, so file-static storage is safe here.
struct CallbackStrings {
    std::string device_id;
    std::string device_name;
    std::string chip_name;
    std::string response_body;
    std::string response_error;
};

CallbackStrings& strings() {
    static CallbackStrings state;
    return state;
}

void device_get_info(rac_device_registration_info_t* out_info, void* /*user_data*/) {
    if (out_info == nullptr) {
        return;
    }
    CallbackStrings& state = strings();
    state.device_name = query_hostname();
    state.chip_name = query_chip_name();

    *out_info = {};
    out_info->device_model = rac_desktop_device_model();
    out_info->device_name = state.device_name.c_str();
    out_info->platform = rac_desktop_platform_name();
    out_info->os_version = rac_desktop_os_version();
    out_info->form_factor = "desktop";
    out_info->architecture = architecture_name();
    out_info->chip_name = state.chip_name.empty() ? nullptr : state.chip_name.c_str();

    rac_memory_info_t memory{};
    const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
    if (adapter != nullptr && adapter->get_memory_info != nullptr &&
        adapter->get_memory_info(&memory, adapter->user_data) == RAC_SUCCESS) {
        out_info->total_memory = static_cast<int64_t>(memory.total_bytes);
        out_info->available_memory = static_cast<int64_t>(memory.available_bytes);
    }

#if defined(__APPLE__) && (defined(__arm64__) || defined(__aarch64__))
    out_info->gpu_family = "apple";
#endif
    // Desktop exposes no portable battery or NPU inventory: report unavailable
    // rather than guessing. -1 battery becomes null on the wire.
    out_info->battery_level = -1.0;
    out_info->core_count = static_cast<int32_t>(std::thread::hardware_concurrency());
}

const char* device_get_id(void* /*user_data*/) {
    CallbackStrings& state = strings();
    const char* state_id = rac_state_get_device_id();
    state.device_id = state_id != nullptr ? state_id : "";
    if (state.device_id.empty()) {
        // A host that initialized state without an id still gets one: commons
        // mints and persists it through the same secure store.
        char minted[RAC_DEVICE_ID_BUFFER_MIN_SIZE] = {};
        if (rac_device_get_or_create_persistent_id(minted, sizeof(minted)) == RAC_SUCCESS) {
            state.device_id = minted;
        }
    }
    return state.device_id.c_str();
}

rac_bool_t device_is_registered(void* /*user_data*/) {
    if (rac_state_is_device_registered()) {
        return RAC_TRUE;
    }
    const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
    if (adapter == nullptr || adapter->secure_get == nullptr) {
        return RAC_FALSE;
    }
    char* stored = nullptr;
    if (adapter->secure_get(kRegisteredKey, &stored, adapter->user_data) != RAC_SUCCESS ||
        stored == nullptr) {
        return RAC_FALSE;
    }
    const bool registered = stored[0] == '1';
    rac_free(stored);
    if (registered) {
        rac_state_set_device_registered(true);
    }
    return registered ? RAC_TRUE : RAC_FALSE;
}

void device_set_registered(rac_bool_t registered, void* /*user_data*/) {
    rac_state_set_device_registered(registered == RAC_TRUE);
    const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
    if (adapter == nullptr) {
        return;
    }
    if (registered == RAC_TRUE) {
        if (adapter->secure_set != nullptr) {
            adapter->secure_set(kRegisteredKey, "1", adapter->user_data);
        }
    } else if (adapter->secure_delete != nullptr) {
        adapter->secure_delete(kRegisteredKey, adapter->user_data);
    }
}

rac_result_t device_http_post(const char* endpoint, const char* json_body, rac_bool_t requires_auth,
                              rac_device_http_response_t* out_response, void* /*user_data*/) {
    if (endpoint == nullptr || json_body == nullptr || out_response == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    CallbackStrings& state = strings();
    state.response_body.clear();
    state.response_error.clear();
    *out_response = {};

    const char* base_url = rac_state_get_base_url();
    if (base_url == nullptr || base_url[0] == '\0' ||
        rac_http_transport_is_registered() != RAC_TRUE) {
        state.response_error = "no HTTP transport or base URL for device registration";
        out_response->result = RAC_ERROR_INVALID_CONFIGURATION;
        out_response->error_message = state.response_error.c_str();
        return out_response->result;
    }

    char url[2048] = {};
    if (rac_build_url(base_url, endpoint, url, sizeof(url)) < 0) {
        state.response_error = "device registration URL build failed";
        out_response->result = RAC_ERROR_INVALID_CONFIGURATION;
        out_response->error_message = state.response_error.c_str();
        return out_response->result;
    }

    // Canonical control-plane header set: commons defaults (Content-Type /
    // Accept / X-SDK-*) + X-Platform + apikey, plus the bearer token when the
    // endpoint requires it.
    std::vector<rac_http_header_kv_t> headers;
    const rac_http_header_kv_t* defaults = nullptr;
    size_t default_count = 0;
    if (rac_http_default_headers(&defaults, &default_count) == RAC_SUCCESS && defaults != nullptr) {
        headers.assign(defaults, defaults + default_count);
    }
    headers.push_back({"X-Platform", rac_desktop_platform_name()});
    const char* api_key = rac_state_get_api_key();
    if (api_key != nullptr && api_key[0] != '\0') {
        headers.push_back({"apikey", api_key});
    }
    std::string bearer;
    if (requires_auth == RAC_TRUE) {
        const char* token = rac_auth_get_access_token();
        if (token != nullptr && token[0] != '\0') {
            bearer = std::string("Bearer ") + token;
            headers.push_back({"Authorization", bearer.c_str()});
        }
    }

    rac_http_client_t* client = nullptr;
    rac_result_t rc = rac_http_client_create(&client);
    if (rc != RAC_SUCCESS) {
        out_response->result = rc;
        return rc;
    }

    rac_http_request_t request = {};
    request.method = "POST";
    request.url = url;
    request.headers = headers.data();
    request.header_count = headers.size();
    request.body_bytes = reinterpret_cast<const uint8_t*>(json_body);
    request.body_len = std::strlen(json_body);
    request.timeout_ms = rac_env_default_http_timeout_ms(rac_state_get_environment());
    // The payload carries the API key and bearer token: never replay it across
    // a redirect.
    request.follow_redirects = RAC_FALSE;

    rac_http_response_t response = {};
    rc = rac_http_request_send(client, &request, &response);
    rac_http_client_destroy(client);

    // rac_http_response_free zeroes the struct, so snapshot the status first.
    const int32_t status = response.status;
    if (response.body_bytes != nullptr && response.body_len > 0) {
        state.response_body.assign(reinterpret_cast<const char*>(response.body_bytes),
                                   response.body_len);
    }
    rac_http_response_free(&response);
    out_response->status_code = status;
    out_response->response_body =
        state.response_body.empty() ? nullptr : state.response_body.c_str();

    if (rc == RAC_SUCCESS && status >= 200 && status < 300) {
        out_response->result = RAC_SUCCESS;
        return RAC_SUCCESS;
    }
    state.response_error = rc != RAC_SUCCESS
                               ? "device registration transport failure"
                               : "device registration rejected with HTTP " + std::to_string(status);
    out_response->result = rc != RAC_SUCCESS ? rc : RAC_ERROR_HTTP_ERROR;
    out_response->error_message = state.response_error.c_str();
    return out_response->result;
}

}  // namespace

extern "C" {

const char* rac_desktop_platform_name(void) {
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

const char* rac_desktop_device_model(void) {
    static const std::string model = query_device_model();
    return model.c_str();
}

const char* rac_desktop_os_version(void) {
    static const std::string version = query_os_version();
    return version.c_str();
}

}  // extern "C"

namespace rac::desktop {

rac_result_t install_device_manager_provider() {
    // These callbacks are plain C and callable from any thread, which is the
    // precondition for stamping telemetry events with live battery/RAM.
    rac_telemetry_enable_live_platform_sampling();

    rac_device_callbacks_t callbacks = {};
    callbacks.get_device_info = device_get_info;
    callbacks.get_device_id = device_get_id;
    callbacks.is_registered = device_is_registered;
    callbacks.set_registered = device_set_registered;
    callbacks.http_post = device_http_post;
    callbacks.user_data = nullptr;
    return rac_device_manager_set_callbacks(&callbacks);
}

}  // namespace rac::desktop
