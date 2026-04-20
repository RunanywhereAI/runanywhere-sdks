// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_platform_llm.h"

#include <array>
#include <atomic>
#include <mutex>

namespace {
constexpr std::size_t kMaxBackends = 8;
std::mutex                                      g_mu;
std::array<ra_platform_llm_callbacks_t, kMaxBackends> g_callbacks{};
std::array<bool, kMaxBackends>                  g_set{};
std::array<bool, kMaxBackends>                  g_registered{};

bool valid(ra_platform_llm_backend_t backend) {
    return backend >= 0 && static_cast<std::size_t>(backend) < kMaxBackends;
}
}  // namespace

extern "C" {

ra_status_t ra_platform_llm_set_callbacks(ra_platform_llm_backend_t backend,
                                           const ra_platform_llm_callbacks_t* callbacks) {
    if (!valid(backend) || !callbacks) return RA_ERR_INVALID_ARGUMENT;
    std::lock_guard lock(g_mu);
    g_callbacks[backend] = *callbacks;
    g_set[backend]       = true;
    return RA_OK;
}

const ra_platform_llm_callbacks_t* ra_platform_llm_get_callbacks(
    ra_platform_llm_backend_t backend) {
    if (!valid(backend)) return nullptr;
    std::lock_guard lock(g_mu);
    return g_set[backend] ? &g_callbacks[backend] : nullptr;
}

uint8_t ra_platform_llm_is_available(ra_platform_llm_backend_t backend,
                                      const ra_model_spec_t* spec) {
    if (!valid(backend)) return 0;
    std::lock_guard lock(g_mu);
    if (!g_set[backend]) return 0;
    auto& cb = g_callbacks[backend];
    if (cb.can_handle && spec) return cb.can_handle(spec, cb.user_data);
    return 1;
}

ra_status_t ra_platform_llm_create(ra_platform_llm_backend_t backend,
                                    const ra_model_spec_t*    spec,
                                    const ra_session_config_t* cfg,
                                    ra_platform_llm_session_t** out_session) {
    if (!valid(backend) || !out_session) return RA_ERR_INVALID_ARGUMENT;
    std::lock_guard lock(g_mu);
    if (!g_set[backend] || !g_callbacks[backend].create)
        return RA_ERR_BACKEND_UNAVAILABLE;
    return g_callbacks[backend].create(spec, cfg, out_session, g_callbacks[backend].user_data);
}

void ra_platform_llm_destroy(ra_platform_llm_backend_t backend,
                              ra_platform_llm_session_t* session) {
    if (!valid(backend) || !session) return;
    std::lock_guard lock(g_mu);
    if (!g_set[backend] || !g_callbacks[backend].destroy) return;
    g_callbacks[backend].destroy(session, g_callbacks[backend].user_data);
}

ra_status_t ra_platform_llm_generate(ra_platform_llm_backend_t backend,
                                       ra_platform_llm_session_t* session,
                                       const ra_prompt_t*         prompt,
                                       ra_token_callback_t        on_token,
                                       ra_error_callback_t        on_error,
                                       void*                      user_data) {
    if (!valid(backend)) return RA_ERR_INVALID_ARGUMENT;
    std::lock_guard lock(g_mu);
    if (!g_set[backend] || !g_callbacks[backend].generate)
        return RA_ERR_BACKEND_UNAVAILABLE;
    return g_callbacks[backend].generate(session, prompt, on_token, on_error,
                                          user_data, g_callbacks[backend].user_data);
}

ra_status_t ra_backend_platform_register(ra_platform_llm_backend_t backend) {
    if (!valid(backend)) return RA_ERR_INVALID_ARGUMENT;
    std::lock_guard lock(g_mu);
    if (!g_set[backend]) return RA_ERR_BACKEND_UNAVAILABLE;
    g_registered[backend] = true;
    return RA_OK;
}

ra_status_t ra_backend_platform_unregister(ra_platform_llm_backend_t backend) {
    if (!valid(backend)) return RA_ERR_INVALID_ARGUMENT;
    std::lock_guard lock(g_mu);
    g_registered[backend] = false;
    return RA_OK;
}

}  // extern "C"
