// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "environment.h"

#include <ctime>

namespace ra::core::net {

Endpoints default_endpoints_for(Environment env) {
    Endpoints e;
    switch (env) {
        case Environment::kDev:
            e.api_base_url       = "http://localhost:8080";
            e.models_catalog_url = "http://localhost:8080/v1/models";
            e.telemetry_url      = "http://localhost:8080/v1/events";
            e.auth_url           = "http://localhost:8080/v1/auth";
            break;
        case Environment::kStaging:
            e.api_base_url       = "https://api.staging.runanywhere.ai";
            e.models_catalog_url = "https://api.staging.runanywhere.ai/v1/models";
            e.telemetry_url      = "https://telemetry.staging.runanywhere.ai/v1/events";
            e.auth_url           = "https://api.staging.runanywhere.ai/v1/auth";
            break;
        case Environment::kProd:
            // defaults from header
            break;
    }
    return e;
}

AuthManager& AuthManager::global() {
    static AuthManager inst;
    return inst;
}

void AuthManager::set_api_key(std::string_view key) {
    std::lock_guard<std::mutex> lk(mu_);
    api_key_ = key;
}

std::string AuthManager::api_key() const {
    std::lock_guard<std::mutex> lk(mu_);
    return api_key_;
}

bool AuthManager::has_api_key() const {
    std::lock_guard<std::mutex> lk(mu_);
    return !api_key_.empty();
}

void AuthManager::set_environment(Environment env) {
    std::lock_guard<std::mutex> lk(mu_);
    env_       = env;
    endpoints_ = default_endpoints_for(env);
}

Environment AuthManager::environment() const {
    std::lock_guard<std::mutex> lk(mu_);
    return env_;
}

Endpoints& AuthManager::endpoints() {
    std::lock_guard<std::mutex> lk(mu_);
    return endpoints_;
}

const Endpoints& AuthManager::endpoints() const {
    std::lock_guard<std::mutex> lk(mu_);
    return endpoints_;
}

void AuthManager::set_tokens(AuthTokens tokens) {
    std::lock_guard<std::mutex> lk(mu_);
    tokens_ = std::move(tokens);
}

AuthTokens AuthManager::tokens() const {
    std::lock_guard<std::mutex> lk(mu_);
    return tokens_;
}

void AuthManager::clear_tokens() {
    std::lock_guard<std::mutex> lk(mu_);
    tokens_ = AuthTokens{};
}

bool AuthManager::is_authenticated() const {
    std::lock_guard<std::mutex> lk(mu_);
    if (tokens_.access_token.empty()) return false;
    if (tokens_.expires_at_unix == 0) return true;  // no declared expiry
    return std::time(nullptr) < tokens_.expires_at_unix;
}

bool AuthManager::token_needs_refresh(int horizon_seconds) const {
    std::lock_guard<std::mutex> lk(mu_);
    if (tokens_.access_token.empty()) return false;
    if (tokens_.expires_at_unix == 0) return false;
    return std::time(nullptr) + horizon_seconds >= tokens_.expires_at_unix;
}

void AuthManager::set_device_id(std::string_view id) {
    std::lock_guard<std::mutex> lk(mu_);
    device_id_ = id;
}

std::string AuthManager::device_id() const {
    std::lock_guard<std::mutex> lk(mu_);
    return device_id_;
}

void AuthManager::set_device_registered(bool registered) {
    std::lock_guard<std::mutex> lk(mu_);
    device_registered_ = registered;
}

bool AuthManager::is_device_registered() const {
    std::lock_guard<std::mutex> lk(mu_);
    return device_registered_;
}

}  // namespace ra::core::net
