// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_state.h"

#include "ra_core_init.h"

#include "../net/environment.h"

#include <atomic>
#include <cstring>
#include <mutex>
#include <string>

using ra::core::net::AuthManager;
using ra::core::net::AuthTokens;
using ra::core::net::Environment;

namespace {

// Thread-safe storage for returned C strings. The AuthManager returns
// std::string by value; the C ABI must return a pointer that stays
// valid at least until the next call to the same getter. We stash
// copies in thread-local buffers — avoids ownership questions.
thread_local std::string tls_api_key;
thread_local std::string tls_base_url;
thread_local std::string tls_device_id;
thread_local std::string tls_access_token;
thread_local std::string tls_refresh_token;
thread_local std::string tls_user_id;
thread_local std::string tls_organization_id;

std::atomic<ra_auth_changed_callback_t>  g_auth_changed_cb{nullptr};
std::atomic<void*>                       g_auth_changed_ud{nullptr};

std::atomic<ra_state_persist_callback_t> g_persist_cb{nullptr};
std::atomic<ra_state_load_callback_t>    g_load_cb{nullptr};
std::atomic<void*>                       g_persist_ud{nullptr};

std::atomic<bool>                        g_last_auth_state{false};

Environment map_env(ra_environment_t e) {
    switch (e) {
        case RA_ENVIRONMENT_DEVELOPMENT: return Environment::kDev;
        case RA_ENVIRONMENT_STAGING:     return Environment::kStaging;
        default:                         return Environment::kProd;
    }
}

ra_environment_t unmap_env(Environment e) {
    switch (e) {
        case Environment::kDev:     return RA_ENVIRONMENT_DEVELOPMENT;
        case Environment::kStaging: return RA_ENVIRONMENT_STAGING;
        default:                    return RA_ENVIRONMENT_PRODUCTION;
    }
}

const char* persist_load(const char* key) {
    auto load = g_load_cb.load();
    if (!load) return nullptr;
    return load(key, g_persist_ud.load());
}

void persist_save(const char* key, const char* value) {
    auto save = g_persist_cb.load();
    if (!save) return;
    save(key, value, g_persist_ud.load());
}

void notify_auth_changed() {
    const bool now = AuthManager::global().is_authenticated();
    const bool was = g_last_auth_state.exchange(now);
    if (was == now) return;
    auto cb = g_auth_changed_cb.load();
    if (cb) cb(now, g_auth_changed_ud.load());
}

}  // namespace

extern "C" {

// ----------------------------------------------------------------------------
// Init / shutdown
// ----------------------------------------------------------------------------

ra_status_t ra_state_initialize(ra_environment_t env, const char* api_key,
                                 const char* base_url, const char* device_id) {
    auto& mgr = AuthManager::global();
    mgr.set_environment(map_env(env));
    if (api_key)   mgr.set_api_key(api_key);
    if (device_id) mgr.set_device_id(device_id);
    if (base_url && *base_url) {
        mgr.endpoints().api_base_url = base_url;
    }

    // Rehydrate persisted tokens via the platform adapter's load callback.
    if (const char* access = persist_load("ra.access_token"); access && *access) {
        AuthTokens t;
        t.access_token = access;
        if (const char* refresh = persist_load("ra.refresh_token")) {
            t.refresh_token = refresh ? refresh : "";
        }
        if (const char* expires = persist_load("ra.expires_at")) {
            t.expires_at_unix = expires ? std::atoll(expires) : 0;
        }
        if (const char* u = persist_load("ra.user_id"))  t.user_id = u ? u : "";
        if (const char* o = persist_load("ra.organization_id")) t.organization_id = o ? o : "";
        mgr.set_tokens(std::move(t));
        g_last_auth_state.store(mgr.is_authenticated());
    }

    // Init the public init stub too so ra_is_initialized() agrees.
    ra_init_config_t cfg{};
    cfg.api_key   = api_key;
    cfg.base_url  = base_url;
    cfg.log_level = RA_LOG_LEVEL_INFO;
    return ra_init(&cfg);
}

bool ra_state_is_initialized(void) { return ra_is_initialized(); }

void ra_state_reset(void) {
    auto& mgr = AuthManager::global();
    mgr.clear_tokens();
    mgr.set_api_key("");
    mgr.set_device_id("");
    mgr.set_device_registered(false);
    g_last_auth_state.store(false);
}

void ra_state_shutdown(void) { ra_shutdown(); }

// ----------------------------------------------------------------------------
// Queries
// ----------------------------------------------------------------------------

ra_environment_t ra_state_get_environment(void) {
    return unmap_env(AuthManager::global().environment());
}

const char* ra_state_get_base_url(void) {
    tls_base_url = AuthManager::global().endpoints().api_base_url;
    return tls_base_url.c_str();
}

const char* ra_state_get_api_key(void) {
    tls_api_key = AuthManager::global().api_key();
    return tls_api_key.c_str();
}

const char* ra_state_get_device_id(void) {
    tls_device_id = AuthManager::global().device_id();
    return tls_device_id.c_str();
}

// ----------------------------------------------------------------------------
// Auth
// ----------------------------------------------------------------------------

ra_status_t ra_state_set_auth(const ra_auth_data_t* auth) {
    if (!auth) return RA_ERR_INVALID_ARGUMENT;
    AuthTokens t;
    if (auth->access_token)    t.access_token    = auth->access_token;
    if (auth->refresh_token)   t.refresh_token   = auth->refresh_token;
    t.expires_at_unix = auth->expires_at_unix;
    if (auth->user_id)         t.user_id         = auth->user_id;
    if (auth->organization_id) t.organization_id = auth->organization_id;
    AuthManager::global().set_tokens(t);

    if (auth->device_id) {
        AuthManager::global().set_device_id(auth->device_id);
    }

    // Persist via callback.
    persist_save("ra.access_token",    auth->access_token ? auth->access_token : "");
    persist_save("ra.refresh_token",   auth->refresh_token ? auth->refresh_token : "");
    {
        char buf[32];
        std::snprintf(buf, sizeof(buf), "%lld",
                      static_cast<long long>(auth->expires_at_unix));
        persist_save("ra.expires_at", buf);
    }
    persist_save("ra.user_id",          auth->user_id ? auth->user_id : "");
    persist_save("ra.organization_id",  auth->organization_id ? auth->organization_id : "");

    notify_auth_changed();
    return RA_OK;
}

const char* ra_state_get_access_token(void) {
    tls_access_token = AuthManager::global().tokens().access_token;
    return tls_access_token.c_str();
}

const char* ra_state_get_refresh_token(void) {
    tls_refresh_token = AuthManager::global().tokens().refresh_token;
    return tls_refresh_token.c_str();
}

bool ra_state_is_authenticated(void) {
    return AuthManager::global().is_authenticated();
}

bool ra_state_token_needs_refresh(int horizon_seconds) {
    return AuthManager::global().token_needs_refresh(horizon_seconds);
}

int64_t ra_state_get_token_expires_at(void) {
    return AuthManager::global().tokens().expires_at_unix;
}

const char* ra_state_get_user_id(void) {
    tls_user_id = AuthManager::global().tokens().user_id;
    return tls_user_id.c_str();
}

const char* ra_state_get_organization_id(void) {
    tls_organization_id = AuthManager::global().tokens().organization_id;
    return tls_organization_id.c_str();
}

void ra_state_clear_auth(void) {
    AuthManager::global().clear_tokens();
    persist_save("ra.access_token", "");
    persist_save("ra.refresh_token", "");
    persist_save("ra.expires_at", "0");
    persist_save("ra.user_id", "");
    persist_save("ra.organization_id", "");
    notify_auth_changed();
}

// ----------------------------------------------------------------------------
// Device registration
// ----------------------------------------------------------------------------

void ra_state_set_device_registered(bool registered) {
    AuthManager::global().set_device_registered(registered);
}

bool ra_state_is_device_registered(void) {
    return AuthManager::global().is_device_registered();
}

// ----------------------------------------------------------------------------
// Callbacks
// ----------------------------------------------------------------------------

void ra_state_on_auth_changed(ra_auth_changed_callback_t callback, void* user_data) {
    g_auth_changed_cb.store(callback);
    g_auth_changed_ud.store(user_data);
}

void ra_state_set_persistence_callbacks(ra_state_persist_callback_t persist,
                                         ra_state_load_callback_t    load,
                                         void*                       user_data) {
    g_persist_cb.store(persist);
    g_load_cb.store(load);
    g_persist_ud.store(user_data);
}

}  // extern "C"
