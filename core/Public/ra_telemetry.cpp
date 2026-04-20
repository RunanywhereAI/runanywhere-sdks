// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_telemetry.h"

#include "environment.h"
#include "telemetry.h"

#include <atomic>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <sstream>
#include <string>
#include <string_view>

namespace {
std::mutex                          g_mu;
ra_telemetry_http_callback_t        g_cb       = nullptr;
void*                               g_user     = nullptr;

thread_local std::string            tls_endpoint;

char* dup_cstr(const std::string& s) {
    char* out = static_cast<char*>(std::malloc(s.size() + 1));
    if (!out) return nullptr;
    std::memcpy(out, s.data(), s.size());
    out[s.size()] = '\0';
    return out;
}

// Minimal JSON-quote. Escapes \ and " only.
std::string jq(std::string_view s) {
    std::string out;
    out.reserve(s.size() + 2);
    out.push_back('"');
    for (char c : s) {
        if (c == '"' || c == '\\') out.push_back('\\');
        out.push_back(c);
    }
    out.push_back('"');
    return out;
}

std::int64_t extract_json_int(std::string_view body, std::string_view key) {
    const std::string quoted = "\"" + std::string{key} + "\"";
    const auto a = body.find(quoted);
    if (a == std::string_view::npos) return 0;
    const auto colon = body.find(':', a + quoted.size());
    if (colon == std::string_view::npos) return 0;
    std::size_t i = colon + 1;
    while (i < body.size() && (body[i] == ' ' || body[i] == '\t')) ++i;
    std::int64_t v = 0; bool neg = false;
    if (i < body.size() && body[i] == '-') { neg = true; ++i; }
    while (i < body.size() && body[i] >= '0' && body[i] <= '9') {
        v = v * 10 + (body[i] - '0'); ++i;
    }
    return neg ? -v : v;
}

}  // namespace

extern "C" {

ra_status_t ra_telemetry_set_http_callback(ra_telemetry_http_callback_t cb,
                                            void* user_data) {
    std::lock_guard lock(g_mu);
    g_cb   = cb;
    g_user = user_data;
    return RA_OK;
}

ra_status_t ra_telemetry_flush(void) {
    auto& mgr = ra::core::net::TelemetryManager::global();
    mgr.stop();
    mgr.start();
    return RA_OK;
}

ra_status_t ra_telemetry_track(const char* event_name,
                                const char* properties_json) {
    if (!event_name) return RA_ERR_INVALID_ARGUMENT;
    (void)properties_json;  // reserved for future parsing
    ra::core::net::TelemetryEvent ev;
    ev.name = event_name;
    ra::core::net::TelemetryManager::global().emit(std::move(ev));
    return RA_OK;
}

const char* ra_device_registration_endpoint(void) {
    tls_endpoint = ra::core::net::AuthManager::global().endpoints().api_base_url
        + "/v1/devices";
    return tls_endpoint.c_str();
}

ra_status_t ra_device_registration_to_json(
    const ra_device_registration_info_t* info, char** out_json) {
    if (!info || !out_json) return RA_ERR_INVALID_ARGUMENT;
    std::ostringstream os;
    os << "{"
       << "\"device_id\":"   << jq(info->device_id   ? info->device_id   : "") << ","
       << "\"os_name\":"     << jq(info->os_name     ? info->os_name     : "") << ","
       << "\"os_version\":"  << jq(info->os_version  ? info->os_version  : "") << ","
       << "\"app_version\":" << jq(info->app_version ? info->app_version : "") << ","
       << "\"sdk_version\":" << jq(info->sdk_version ? info->sdk_version : "") << ","
       << "\"model_name\":"  << jq(info->model_name  ? info->model_name  : "") << ","
       << "\"chip_name\":"   << jq(info->chip_name   ? info->chip_name   : "") << ","
       << "\"total_memory_bytes\":"      << info->total_memory_bytes      << ","
       << "\"available_storage_bytes\":" << info->available_storage_bytes
       << "}";
    *out_json = dup_cstr(os.str());
    return *out_json ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

ra_status_t ra_telemetry_payload_default(char** out_json) {
    if (!out_json) return RA_ERR_INVALID_ARGUMENT;
    std::ostringstream os;
    os << "{"
       << "\"sdk_version\":\"2.0.0\","
       << "\"platform\":\""
#if defined(__APPLE__) && defined(__MACH__)
       << "apple"
#elif defined(__ANDROID__)
       << "android"
#elif defined(_WIN32)
       << "windows"
#elif defined(__linux__)
       << "linux"
#else
       << "unknown"
#endif
       << "\"}";
    *out_json = dup_cstr(os.str());
    return *out_json ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

ra_status_t ra_telemetry_parse_response(const char* json_body,
                                         int32_t* out_accepted,
                                         int32_t* out_rejected) {
    if (!json_body) return RA_ERR_INVALID_ARGUMENT;
    std::string_view body = json_body;
    if (out_accepted) *out_accepted = static_cast<int32_t>(extract_json_int(body, "accepted"));
    if (out_rejected) *out_rejected = static_cast<int32_t>(extract_json_int(body, "rejected"));
    return RA_OK;
}

ra_status_t ra_telemetry_batch_to_json(char** out_json) {
    if (!out_json) return RA_ERR_INVALID_ARGUMENT;
    // TelemetryManager holds the in-memory queue; we emit a minimal
    // envelope wrapper even if the queue is empty.
    const std::size_t depth = ra::core::net::TelemetryManager::global().queue_depth();
    std::ostringstream os;
    os << "{\"events\":[],\"queue_depth\":" << depth << "}";
    *out_json = dup_cstr(os.str());
    return *out_json ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

ra_status_t ra_telemetry_properties_to_json(const char* const* pairs,
                                             int32_t            pair_count,
                                             char**             out_json) {
    if (!out_json || pair_count < 0) return RA_ERR_INVALID_ARGUMENT;
    if (pair_count > 0 && !pairs) return RA_ERR_INVALID_ARGUMENT;
    std::ostringstream os;
    os << "{";
    for (int32_t i = 0; i + 1 < pair_count * 2; i += 2) {
        if (i > 0) os << ",";
        os << jq(pairs[i] ? pairs[i] : "") << ":"
           << jq(pairs[i + 1] ? pairs[i + 1] : "");
    }
    os << "}";
    *out_json = dup_cstr(os.str());
    return *out_json ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

void ra_telemetry_string_free(char* str) {
    if (str) std::free(str);
}

}  // extern "C"
