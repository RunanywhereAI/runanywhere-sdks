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

private:
    AuthManager() : endpoints_(default_endpoints_for(Environment::kProd)) {}

    mutable std::mutex  mu_;
    std::string         api_key_;
    Environment         env_ = Environment::kProd;
    Endpoints           endpoints_;
};

}  // namespace ra::core::net

#endif  // RA_CORE_NET_ENVIRONMENT_H
