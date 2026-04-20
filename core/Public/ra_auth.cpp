// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_auth.h"
#include "ra_state.h"
#include "ra_platform_adapter.h"

#include "environment.h"

#include <cstdlib>
#include <cstring>
#include <ctime>
#include <sstream>
#include <string>
#include <string_view>

using ra::core::net::AuthManager;
using ra::core::net::AuthTokens;

namespace {

// Same thread-local buffer pattern used elsewhere in ra_state.cpp so
// C-string returns stay valid until the next call on the same thread.
thread_local std::string tls_access_token;
thread_local std::string tls_refresh_token;
thread_local std::string tls_device_id;
thread_local std::string tls_user_id;
thread_local std::string tls_organization_id;
thread_local std::string tls_valid_token;

char* dup_cstr(const std::string& s) {
    char* out = static_cast<char*>(std::malloc(s.size() + 1));
    if (!out) return nullptr;
    std::memcpy(out, s.data(), s.size());
    out[s.size()] = '\0';
    return out;
}

// Minimal JSON string extractor — no full parser dep. Finds "key":"value"
// substring and returns the value. Returns empty on mismatch.
std::string extract_json_string(std::string_view body, std::string_view key) {
    const std::string quoted = "\"" + std::string{key} + "\"";
    const auto a = body.find(quoted);
    if (a == std::string_view::npos) return "";
    const auto colon = body.find(':', a + quoted.size());
    if (colon == std::string_view::npos) return "";
    const auto q1 = body.find('"', colon + 1);
    if (q1 == std::string_view::npos) return "";
    const auto q2 = body.find('"', q1 + 1);
    if (q2 == std::string_view::npos) return "";
    return std::string{body.substr(q1 + 1, q2 - q1 - 1)};
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
        v = v * 10 + (body[i] - '0');
        ++i;
    }
    return neg ? -v : v;
}

// JSON-quote a string. Minimal — escapes backslash + double-quote only.
std::string json_quote(std::string_view s) {
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

}  // namespace

extern "C" {

ra_status_t ra_auth_init(void) {
    (void)AuthManager::global();  // touch singleton
    return RA_OK;
}

ra_status_t ra_auth_reset(void) {
    AuthManager::global().clear_tokens();
    return RA_OK;
}

uint8_t ra_auth_is_authenticated(void) {
    return AuthManager::global().is_authenticated() ? 1 : 0;
}

uint8_t ra_auth_needs_refresh(int32_t horizon_seconds) {
    const int h = horizon_seconds > 0 ? horizon_seconds : 60;
    return AuthManager::global().token_needs_refresh(h) ? 1 : 0;
}

const char* ra_auth_get_access_token(void) {
    tls_access_token = AuthManager::global().tokens().access_token;
    return tls_access_token.c_str();
}

const char* ra_auth_get_refresh_token(void) {
    tls_refresh_token = AuthManager::global().tokens().refresh_token;
    return tls_refresh_token.c_str();
}

const char* ra_auth_get_device_id(void) {
    tls_device_id = AuthManager::global().device_id();
    return tls_device_id.c_str();
}

const char* ra_auth_get_user_id(void) {
    tls_user_id = AuthManager::global().tokens().user_id;
    return tls_user_id.c_str();
}

const char* ra_auth_get_organization_id(void) {
    tls_organization_id = AuthManager::global().tokens().organization_id;
    return tls_organization_id.c_str();
}

ra_status_t ra_auth_build_authenticate_request(const char* api_key,
                                                 const char* device_id,
                                                 char**      out_body) {
    if (!out_body) return RA_ERR_INVALID_ARGUMENT;
    std::ostringstream os;
    os << "{"
       << "\"api_key\":" << json_quote(api_key ? api_key : "") << ","
       << "\"device_id\":" << json_quote(device_id ? device_id : "")
       << "}";
    *out_body = dup_cstr(os.str());
    return *out_body ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

ra_status_t ra_auth_build_refresh_request(char** out_body) {
    if (!out_body) return RA_ERR_INVALID_ARGUMENT;
    const auto tokens = AuthManager::global().tokens();
    std::ostringstream os;
    os << "{\"refresh_token\":" << json_quote(tokens.refresh_token) << "}";
    *out_body = dup_cstr(os.str());
    return *out_body ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

ra_status_t ra_auth_handle_authenticate_response(const char* json_body) {
    if (!json_body) return RA_ERR_INVALID_ARGUMENT;
    std::string_view body = json_body;
    AuthTokens t;
    t.access_token    = extract_json_string(body, "access_token");
    t.refresh_token   = extract_json_string(body, "refresh_token");
    t.user_id         = extract_json_string(body, "user_id");
    t.organization_id = extract_json_string(body, "organization_id");
    const auto expiresIn = extract_json_int(body, "expires_in");
    if (expiresIn > 0) {
        t.expires_at_unix = std::time(nullptr) + expiresIn;
    } else {
        t.expires_at_unix = extract_json_int(body, "expires_at");
    }
    if (t.access_token.empty()) return RA_ERR_INVALID_ARGUMENT;
    AuthManager::global().set_tokens(std::move(t));
    return RA_OK;
}

ra_status_t ra_auth_handle_refresh_response(const char* json_body) {
    if (!json_body) return RA_ERR_INVALID_ARGUMENT;
    std::string_view body = json_body;
    auto tokens = AuthManager::global().tokens();
    const auto access = extract_json_string(body, "access_token");
    if (access.empty()) return RA_ERR_INVALID_ARGUMENT;
    tokens.access_token = access;
    if (auto refresh = extract_json_string(body, "refresh_token"); !refresh.empty()) {
        tokens.refresh_token = std::move(refresh);
    }
    const auto expiresIn = extract_json_int(body, "expires_in");
    if (expiresIn > 0) {
        tokens.expires_at_unix = std::time(nullptr) + expiresIn;
    }
    AuthManager::global().set_tokens(std::move(tokens));
    return RA_OK;
}

const char* ra_auth_get_valid_token(void) {
    auto& mgr = AuthManager::global();
    if (!mgr.is_authenticated()) return nullptr;
    tls_valid_token = mgr.tokens().access_token;
    return tls_valid_token.empty() ? nullptr : tls_valid_token.c_str();
}

void ra_auth_clear(void) {
    AuthManager::global().clear_tokens();
}

ra_status_t ra_auth_load_stored_tokens(void) {
    // Delegate to ra_state which already owns persist/load bridging.
    // If the platform adapter has a load callback set, tokens populate on
    // next ra_state_initialize call; here we simply return the current
    // authenticated status so callers know whether tokens are available.
    return AuthManager::global().is_authenticated() ? RA_OK : RA_ERR_CAPABILITY_UNSUPPORTED;
}

ra_status_t ra_auth_save_tokens(void) {
    // ra_state persists on set_tokens. This is the public entry point for
    // hosts that want to re-save the current state explicitly.
    const auto t = AuthManager::global().tokens();
    if (t.access_token.empty()) return RA_ERR_INVALID_ARGUMENT;
    AuthManager::global().set_tokens(t);  // triggers persist via ra_state
    return RA_OK;
}

void ra_auth_string_free(char* str) {
    if (str) std::free(str);
}

}  // extern "C"
