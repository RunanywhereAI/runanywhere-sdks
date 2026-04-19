// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Runtime environment + endpoints + API key holder. Ports the capability
// surface from `sdk/runanywhere-commons/include/rac/infrastructure/network/
// {rac_environment.h,rac_endpoints.h,rac_auth_manager.h}` into a single
// lightweight singleton.

#ifndef RA_CORE_NET_ENVIRONMENT_H
#define RA_CORE_NET_ENVIRONMENT_H

#include <mutex>
#include <optional>
#include <string>
#include <string_view>

namespace ra::core::net {

enum class Environment { kDev, kStaging, kProd };

struct Endpoints {
    std::string api_base_url       = "https://api.runanywhere.ai";
    std::string models_catalog_url = "https://api.runanywhere.ai/v1/models";
    std::string telemetry_url      = "https://telemetry.runanywhere.ai/v1/events";
    std::string auth_url           = "https://api.runanywhere.ai/v1/auth";
};

// Defaults keyed by environment. Frontends can override any individual
// URL via AuthManager::endpoints() after bootstrap.
Endpoints default_endpoints_for(Environment env);

struct AuthTokens {
    std::string  access_token;
    std::string  refresh_token;
    std::int64_t expires_at_unix = 0;  // seconds since epoch
    std::string  user_id;
    std::string  organization_id;
};

class AuthManager {
public:
    static AuthManager& global();

    AuthManager(const AuthManager&) = delete;
    AuthManager& operator=(const AuthManager&) = delete;

    void        set_api_key(std::string_view key);
    std::string api_key() const;
    bool        has_api_key() const;

    void        set_environment(Environment env);
    Environment environment() const;

    // Mutable endpoints — callers can override specific URLs (common on
    // dev builds pointing at a localhost dev server).
    Endpoints&  endpoints();
    const Endpoints& endpoints() const;

    // Auth tokens ----------------------------------------------------------
    //
    // Set after a successful login exchange. `expires_at_unix == 0` means
    // the token has no declared expiry (treated as non-expiring).
    void       set_tokens(AuthTokens tokens);
    AuthTokens tokens() const;
    void       clear_tokens();

    // Returns true if access_token is non-empty and not expired (or has no
    // declared expiry). Uses std::time(NULL) for "now" on every call.
    bool       is_authenticated() const;

    // Returns true when the access token expires within `horizon_seconds`.
    // Callers typically pass 60 to proactively refresh before expiry.
    bool       token_needs_refresh(int horizon_seconds = 60) const;

    // Device registration --------------------------------------------------
    void        set_device_id(std::string_view id);
    std::string device_id() const;
    void        set_device_registered(bool registered);
    bool        is_device_registered() const;

private:
    AuthManager() : endpoints_(default_endpoints_for(Environment::kProd)) {}

    mutable std::mutex  mu_;
    std::string         api_key_;
    Environment         env_ = Environment::kProd;
    Endpoints           endpoints_;
    AuthTokens          tokens_;
    std::string         device_id_;
    bool                device_registered_ = false;
};

}  // namespace ra::core::net

#endif  // RA_CORE_NET_ENVIRONMENT_H
