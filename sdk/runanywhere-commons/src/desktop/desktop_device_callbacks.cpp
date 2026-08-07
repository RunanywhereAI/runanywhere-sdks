/**
 * @file desktop_device_callbacks.cpp
 * @brief Desktop (macOS/Linux/Windows) rac_device_callbacks_t implementation.
 *
 * Mirrors the Swift/Kotlin device-registration bridges (CppBridge+Device /
 * CppBridgeDevice) for desktop hosts (Electron, Python, CLI). Without these
 * callbacks the backend never receives a full /devices/register POST and shows
 * every desktop device as "Unknown / — / —"; commons only ever saw the device
 * id via other endpoints and created a placeholder row.
 *
 *   - get_device_info: fills rac_device_registration_info_t from native probes
 *     (macOS sysctl, Linux /proc + sysinfo, Windows GlobalMemoryStatusEx +
 *     registry).
 *   - get_device_id: the persistent UUID commons already synthesizes.
 *   - is_registered / set_registered: always-register on launch so the backend
 *     upserts fresh metadata (and heals any stale "Unknown" placeholder row).
 *   - http_post: POSTs the registration JSON through the registered transport
 *     (rac_http_client), attaching the SDK bearer token.
 *
 * Depends only on public commons C APIs (no desktop-adapter coupling) so both
 * the Electron addon (via the rac_desktop link) and the Python module (which
 * compiles this file directly with its own urllib transport) can share it.
 */

#include <cstring>
#include <string>
#include <vector>

#include "rac/core/rac_sdk_state.h"
#include "rac/desktop/rac_desktop.h"
#include "rac/infrastructure/device/rac_device_identity.h"
#include "rac/infrastructure/device/rac_device_manager.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/network/rac_auth_manager.h"
#include "rac/infrastructure/network/rac_endpoints.h"

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#else
#include <unistd.h>
#endif

#if defined(__APPLE__)
#include <mach/mach.h>
#include <sys/sysctl.h>
#define RAC_DESKTOP_PLATFORM "macos"
#elif defined(__linux__)
#include <fstream>
#include <sys/sysinfo.h>
#include <sys/utsname.h>
#define RAC_DESKTOP_PLATFORM "linux"
#elif defined(_WIN32)
#define RAC_DESKTOP_PLATFORM "windows"
#else
#define RAC_DESKTOP_PLATFORM "desktop"
#endif

namespace {

// Backing storage for the const char* fields of rac_device_registration_info_t.
// rac_device_manager_register_if_needed() calls get_device_info() and then
// serializes the struct synchronously under its own mutex, so a single
// process-global buffer set is safe: the strings only need to outlive the one
// serialization that immediately follows the fill.
struct DeviceStrings {
    std::string device_model;
    std::string device_name;
    std::string os_version;
    std::string form_factor;
    std::string architecture;
    std::string chip_name;
    std::string gpu_family;
};
DeviceStrings g_strings;

std::string hostname() {
    char buf[256] = {0};
#if defined(_WIN32)
    DWORD len = sizeof(buf);
    if (GetComputerNameA(buf, &len)) {
        return std::string(buf, len);
    }
    return {};
#else
    if (gethostname(buf, sizeof(buf) - 1) == 0) {
        return buf;
    }
    return {};
#endif
}

#if defined(__APPLE__)
std::string sysctl_string(const char* name) {
    size_t len = 0;
    if (sysctlbyname(name, nullptr, &len, nullptr, 0) != 0 || len == 0) {
        return {};
    }
    std::string buf(len, '\0');
    if (sysctlbyname(name, buf.data(), &len, nullptr, 0) != 0) {
        return {};
    }
    if (!buf.empty() && buf.back() == '\0') {
        buf.pop_back();
    }
    return buf;
}

int32_t sysctl_int(const char* name) {
    int32_t value = 0;
    size_t size = sizeof(value);
    if (sysctlbyname(name, &value, &size, nullptr, 0) != 0) {
        return 0;
    }
    return value;
}
#endif

#if defined(__linux__)
std::string cpuinfo_field(const char* const* keys, size_t key_count) {
    std::ifstream cpuinfo("/proc/cpuinfo");
    std::string line;
    while (std::getline(cpuinfo, line)) {
        for (size_t i = 0; i < key_count; ++i) {
            const size_t klen = std::strlen(keys[i]);
            if (line.compare(0, klen, keys[i]) == 0) {
                const size_t colon = line.find(':');
                if (colon != std::string::npos) {
                    std::string value = line.substr(colon + 1);
                    const size_t first = value.find_first_not_of(" \t");
                    const size_t last = value.find_last_not_of(" \t\r\n");
                    if (first != std::string::npos) {
                        return value.substr(first, last - first + 1);
                    }
                }
            }
        }
    }
    return {};
}

std::string read_trimmed(const char* path) {
    std::ifstream f(path);
    std::string value;
    std::getline(f, value);
    const size_t last = value.find_last_not_of(" \t\r\n");
    if (last != std::string::npos) {
        value.erase(last + 1);
    }
    return value;
}
#endif

#if defined(_WIN32)
std::string registry_string(HKEY root, const char* subkey, const char* value) {
    HKEY key = nullptr;
    if (RegOpenKeyExA(root, subkey, 0, KEY_READ, &key) != ERROR_SUCCESS) {
        return {};
    }
    char buf[512] = {0};
    DWORD size = sizeof(buf);
    DWORD type = 0;
    LONG rc = RegQueryValueExA(key, value, nullptr, &type, reinterpret_cast<LPBYTE>(buf), &size);
    RegCloseKey(key);
    if (rc != ERROR_SUCCESS || type != REG_SZ) {
        return {};
    }
    return std::string(buf);
}
#endif

void gather_impl(rac_device_registration_info_t* out) {
    g_strings = DeviceStrings{};
    out->platform = RAC_DESKTOP_PLATFORM;
    g_strings.device_name = hostname();

#if defined(__APPLE__)
    g_strings.device_model = sysctl_string("hw.model");
    g_strings.chip_name = sysctl_string("machdep.cpu.brand_string");
    g_strings.architecture = sysctl_string("hw.machine");
    g_strings.os_version = sysctl_string("kern.osproductversion");
    const bool apple_silicon = g_strings.architecture.rfind("arm", 0) == 0;
    g_strings.form_factor =
        g_strings.device_model.find("Book") != std::string::npos ? "laptop" : "desktop";
    g_strings.gpu_family = apple_silicon ? "apple" : "";
    out->has_neural_engine = apple_silicon ? RAC_TRUE : RAC_FALSE;
    out->neural_engine_cores = apple_silicon ? 16 : 0;
    out->core_count = sysctl_int("hw.logicalcpu");
    out->performance_cores = sysctl_int("hw.perflevel0.logicalcpu");
    out->efficiency_cores = sysctl_int("hw.perflevel1.logicalcpu");

    uint64_t total = 0;
    size_t total_size = sizeof(total);
    if (sysctlbyname("hw.memsize", &total, &total_size, nullptr, 0) == 0) {
        out->total_memory = static_cast<int64_t>(total);
    }
    vm_statistics64_data_t vm{};
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64, reinterpret_cast<host_info64_t>(&vm),
                          &count) == KERN_SUCCESS) {
        vm_size_t page_size = 0;
        host_page_size(mach_host_self(), &page_size);
        out->available_memory = static_cast<int64_t>(
            (static_cast<uint64_t>(vm.free_count) + static_cast<uint64_t>(vm.inactive_count)) *
            static_cast<uint64_t>(page_size));
    }
#elif defined(__linux__)
    g_strings.device_model = read_trimmed("/sys/class/dmi/id/product_name");
    const char* chip_keys[] = {"model name", "Hardware", "Model"};
    g_strings.chip_name = cpuinfo_field(chip_keys, sizeof(chip_keys) / sizeof(chip_keys[0]));
    struct utsname uts{};
    if (uname(&uts) == 0) {
        g_strings.architecture = uts.machine;
        g_strings.os_version = uts.release;
    }
    g_strings.form_factor = "desktop";
    out->has_neural_engine = RAC_FALSE;
    out->neural_engine_cores = 0;
    out->core_count = static_cast<int32_t>(sysconf(_SC_NPROCESSORS_ONLN));

    struct sysinfo si{};
    if (sysinfo(&si) == 0) {
        out->total_memory = static_cast<int64_t>(static_cast<uint64_t>(si.totalram) * si.mem_unit);
        out->available_memory =
            static_cast<int64_t>(static_cast<uint64_t>(si.freeram) * si.mem_unit);
    }
#elif defined(_WIN32)
    g_strings.device_model = registry_string(
        HKEY_LOCAL_MACHINE, "HARDWARE\\DESCRIPTION\\System\\BIOS", "SystemProductName");
    g_strings.chip_name =
        registry_string(HKEY_LOCAL_MACHINE, "HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",
                        "ProcessorNameString");
    g_strings.form_factor = "desktop";
    out->has_neural_engine = RAC_FALSE;
    out->neural_engine_cores = 0;

    SYSTEM_INFO sysinfo{};
    GetNativeSystemInfo(&sysinfo);
    out->core_count = static_cast<int32_t>(sysinfo.dwNumberOfProcessors);
    switch (sysinfo.wProcessorArchitecture) {
        case PROCESSOR_ARCHITECTURE_AMD64:
            g_strings.architecture = "x86_64";
            break;
        case PROCESSOR_ARCHITECTURE_ARM64:
            g_strings.architecture = "arm64";
            break;
        default:
            g_strings.architecture = "x86";
            break;
    }
    g_strings.os_version = registry_string(
        HKEY_LOCAL_MACHINE, "SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion", "CurrentVersion");

    MEMORYSTATUSEX status{};
    status.dwLength = sizeof(status);
    if (GlobalMemoryStatusEx(&status)) {
        out->total_memory = static_cast<int64_t>(status.ullTotalPhys);
        out->available_memory = static_cast<int64_t>(status.ullAvailPhys);
    }
#endif

    out->device_model = g_strings.device_model.c_str();
    out->device_name = g_strings.device_name.c_str();
    out->os_version = g_strings.os_version.c_str();
    out->form_factor = g_strings.form_factor.empty() ? nullptr : g_strings.form_factor.c_str();
    out->architecture = g_strings.architecture.c_str();
    out->chip_name = g_strings.chip_name.c_str();
    out->gpu_family = g_strings.gpu_family.empty() ? nullptr : g_strings.gpu_family.c_str();
    out->battery_level = -1.0;  // desktop: unavailable
}

void device_get_info(rac_device_registration_info_t* out_info, void* /*user_data*/) {
    if (!out_info) {
        return;
    }
    gather_impl(out_info);
}

const char* device_get_id(void* /*user_data*/) {
    static thread_local char id[RAC_DEVICE_ID_BUFFER_MIN_SIZE];
    if (rac_device_get_or_create_persistent_id(id, sizeof(id)) != RAC_SUCCESS) {
        return nullptr;
    }
    return id;
}

// Always register on launch: the backend upserts by device id, so one small
// POST per init keeps the metadata fresh and upgrades any stale placeholder row
// the backend created before these callbacks existed.
rac_bool_t device_is_registered(void* /*user_data*/) { return RAC_FALSE; }

void device_set_registered(rac_bool_t /*registered*/, void* /*user_data*/) {}

rac_result_t device_http_post(const char* endpoint, const char* json_body, rac_bool_t requires_auth,
                              rac_device_http_response_t* out_response, void* /*user_data*/) {
    if (out_response) {
        *out_response = {};
    }
    const char* base_url = rac_state_get_base_url();
    if (!base_url || base_url[0] == '\0') {
        if (out_response) {
            out_response->result = RAC_ERROR_NOT_INITIALIZED;
        }
        return RAC_ERROR_NOT_INITIALIZED;
    }

    char url[1024];
    if (rac_build_url(base_url, endpoint, url, sizeof(url)) != 0) {
        if (out_response) {
            out_response->result = RAC_ERROR_INVALID_ARGUMENT;
        }
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const rac_http_header_kv_t* defaults = nullptr;
    size_t default_count = 0;
    rac_http_default_headers(&defaults, &default_count);
    std::vector<rac_http_header_kv_t> headers(defaults, defaults + default_count);

    std::string bearer;
    if (requires_auth == RAC_TRUE) {
        const char* token = rac_auth_get_access_token();
        if (token && token[0] != '\0') {
            bearer = std::string("Bearer ") + token;
            headers.push_back({"Authorization", bearer.c_str()});
        }
    }
    headers.push_back({"X-Platform", RAC_DESKTOP_PLATFORM});

    rac_http_request_t request = {};
    request.method = "POST";
    request.url = url;
    request.headers = headers.data();
    request.header_count = headers.size();
    request.body_bytes = reinterpret_cast<const uint8_t*>(json_body);
    request.body_len = json_body ? std::strlen(json_body) : 0;
    request.timeout_ms = 30000;
    request.follow_redirects = RAC_FALSE;  // credential-bearing request

    rac_http_client_t* client = nullptr;
    if (rac_http_client_create(&client) != RAC_SUCCESS || !client) {
        if (out_response) {
            out_response->result = RAC_ERROR_INTERNAL;
        }
        return RAC_ERROR_INTERNAL;
    }

    rac_http_response_t response = {};
    const rac_result_t rc = rac_http_request_send(client, &request, &response);
    rac_http_client_destroy(client);

    if (rc != RAC_SUCCESS) {
        if (out_response) {
            out_response->result = rc;
        }
        return rc;
    }

    if (out_response) {
        out_response->status_code = response.status;
        if (response.status >= 200 && response.status < 300) {
            out_response->result = RAC_SUCCESS;
        } else {
            out_response->result = RAC_ERROR_NETWORK_ERROR;
            static thread_local std::string error;
            error = "HTTP " + std::to_string(response.status);
            out_response->error_message = error.c_str();
        }
    }
    rac_http_response_free(&response);
    return RAC_SUCCESS;
}

}  // namespace

extern "C" void rac_desktop_device_info_fill(rac_device_registration_info_t* out_info) {
    if (out_info) {
        gather_impl(out_info);
    }
}

extern "C" rac_result_t rac_desktop_device_callbacks_register(void) {
    rac_device_callbacks_t callbacks = {};
    callbacks.get_device_info = device_get_info;
    callbacks.get_device_id = device_get_id;
    callbacks.is_registered = device_is_registered;
    callbacks.set_registered = device_set_registered;
    callbacks.http_post = device_http_post;
    callbacks.user_data = nullptr;
    return rac_device_manager_set_callbacks(&callbacks);
}
