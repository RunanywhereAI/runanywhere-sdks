// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_server.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <mutex>

namespace {
std::mutex                          g_mu;
std::condition_variable             g_cv;
std::atomic<ra_server_state_t>      g_state{RA_SERVER_STATE_STOPPED};
std::atomic<int32_t>                g_port{0};
std::atomic<int64_t>                g_started_at{0};
std::atomic<int64_t>                g_total_requests{0};

ra_server_request_callback_t        g_req_cb = nullptr;
void*                               g_req_user = nullptr;
ra_server_error_callback_t          g_err_cb = nullptr;
void*                               g_err_user = nullptr;
}  // namespace

extern "C" {

ra_status_t ra_server_start(const ra_server_config_t* config) {
#ifdef RA_BUILD_SERVER
    if (!config) return RA_ERR_INVALID_ARGUMENT;
    if (g_state.load() == RA_SERVER_STATE_RUNNING) return RA_OK;
    g_state = RA_SERVER_STATE_STARTING;
    g_port  = config->port > 0 ? config->port : 8088;
    g_started_at = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
    // The full HTTP loop is implemented in solutions/openai-server/ when
    // RA_BUILD_SERVER is enabled; this ABI just records state. The server
    // implementation calls back into the registered request callback per
    // incoming /v1/* request to delegate handling to the host process.
    g_state = RA_SERVER_STATE_RUNNING;
    g_cv.notify_all();
    return RA_OK;
#else
    (void)config;
    return RA_ERR_CAPABILITY_UNSUPPORTED;
#endif
}

ra_status_t ra_server_stop(void) {
#ifdef RA_BUILD_SERVER
    g_state = RA_SERVER_STATE_STOPPING;
    g_state = RA_SERVER_STATE_STOPPED;
    g_cv.notify_all();
    return RA_OK;
#else
    return RA_ERR_CAPABILITY_UNSUPPORTED;
#endif
}

uint8_t ra_server_is_running(void) {
    return g_state.load() == RA_SERVER_STATE_RUNNING ? 1 : 0;
}

ra_status_t ra_server_get_status(ra_server_status_t* out_status) {
    if (!out_status) return RA_ERR_INVALID_ARGUMENT;
    out_status->state          = g_state.load();
    out_status->port           = g_port.load();
    out_status->started_at_ms  = g_started_at.load();
    out_status->total_requests = g_total_requests.load();
    return RA_OK;
}

ra_status_t ra_server_wait(int32_t timeout_ms) {
#ifdef RA_BUILD_SERVER
    std::unique_lock lock(g_mu);
    auto pred = [] { return g_state.load() == RA_SERVER_STATE_STOPPED; };
    if (timeout_ms < 0) {
        g_cv.wait(lock, pred);
    } else {
        g_cv.wait_for(lock, std::chrono::milliseconds(timeout_ms), pred);
    }
    return RA_OK;
#else
    (void)timeout_ms;
    return RA_ERR_CAPABILITY_UNSUPPORTED;
#endif
}

ra_status_t ra_server_set_request_callback(ra_server_request_callback_t cb, void* user_data) {
    std::lock_guard lock(g_mu);
    g_req_cb   = cb;
    g_req_user = user_data;
    return RA_OK;
}

ra_status_t ra_server_set_error_callback(ra_server_error_callback_t cb, void* user_data) {
    std::lock_guard lock(g_mu);
    g_err_cb   = cb;
    g_err_user = user_data;
    return RA_OK;
}

}  // extern "C"
