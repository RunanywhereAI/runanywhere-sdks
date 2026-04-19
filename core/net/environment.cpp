// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "environment.h"

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

}  // namespace ra::core::net
