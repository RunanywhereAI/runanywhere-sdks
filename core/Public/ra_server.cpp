// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_server.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <mutex>

// Weak-symbol entry points provided by the optional
// `solutions/openai-server/` library. When that lib is linked, these
// resolve to the real start/stop/etc. When not linked, the fallback
// below keeps the ABI stable but reports RA_ERR_CAPABILITY_UNSUPPORTED.

extern "C" {
int32_t ra_solution_openai_server_start(const char* host, int32_t port,
                                           const char* api_key) __attribute__((weak));
void    ra_solution_openai_server_stop(void) __attribute__((weak));
void    ra_solution_openai_server_set_callback(
            ra_server_request_callback_t cb, void* user_data) __attribute__((weak));
int64_t ra_solution_openai_server_total_requests(void) __attribute__((weak));
int64_t ra_solution_openai_server_started_at_ms(void) __attribute__((weak));
}

namespace {
std::mutex                          g_mu;
std::condition_variable             g_cv;
std::atomic<ra_server_state_t>      g_state{RA_SERVER_STATE_STOPPED};
std::atomic<int32_t>                g_port{0};

ra_server_request_callback_t        g_req_cb = nullptr;
void*                               g_req_user = nullptr;
ra_server_error_callback_t          g_err_cb = nullptr;
void*                               g_err_user = nullptr;
}  // namespace

extern "C" {

ra_status_t ra_server_start(const ra_server_config_t* config) {
    if (!config) return RA_ERR_INVALID_ARGUMENT;
    if (g_state.load() == RA_SERVER_STATE_RUNNING) return RA_OK;

    if (!ra_solution_openai_server_start) {
        return RA_ERR_CAPABILITY_UNSUPPORTED;
    }
    g_state = RA_SERVER_STATE_STARTING;
    const int port = ra_solution_openai_server_start(
        config->host ? config->host : "127.0.0.1",
        config->port,
        config->api_key);
    if (port < 0) {
        g_state = RA_SERVER_STATE_FAILED;
        return RA_ERR_IO;
    }
    if (ra_solution_openai_server_set_callback) {
        std::lock_guard lk(g_mu);
        ra_solution_openai_server_set_callback(g_req_cb, g_req_user);
    }
    g_port.store(port);
    g_state = RA_SERVER_STATE_RUNNING;
    g_cv.notify_all();
    return RA_OK;
}

ra_status_t ra_server_stop(void) {
    if (g_state.load() != RA_SERVER_STATE_RUNNING) return RA_OK;
    g_state = RA_SERVER_STATE_STOPPING;
    if (ra_solution_openai_server_stop) ra_solution_openai_server_stop();
    g_state = RA_SERVER_STATE_STOPPED;
    g_cv.notify_all();
    return RA_OK;
}

uint8_t ra_server_is_running(void) {
    return g_state.load() == RA_SERVER_STATE_RUNNING ? 1 : 0;
}

ra_status_t ra_server_get_status(ra_server_status_t* out_status) {
    if (!out_status) return RA_ERR_INVALID_ARGUMENT;
    out_status->state          = g_state.load();
    out_status->port           = g_port.load();
    out_status->started_at_ms  = ra_solution_openai_server_started_at_ms
        ? ra_solution_openai_server_started_at_ms() : 0;
    out_status->total_requests = ra_solution_openai_server_total_requests
        ? ra_solution_openai_server_total_requests() : 0;
    return RA_OK;
}

ra_status_t ra_server_wait(int32_t timeout_ms) {
    std::unique_lock lock(g_mu);
    auto pred = [] { return g_state.load() == RA_SERVER_STATE_STOPPED; };
    if (timeout_ms < 0) {
        g_cv.wait(lock, pred);
    } else {
        g_cv.wait_for(lock, std::chrono::milliseconds(timeout_ms), pred);
    }
    return RA_OK;
}

ra_status_t ra_server_set_request_callback(ra_server_request_callback_t cb,
                                            void* user_data) {
    std::lock_guard lock(g_mu);
    g_req_cb   = cb;
    g_req_user = user_data;
    if (ra_solution_openai_server_set_callback) {
        ra_solution_openai_server_set_callback(cb, user_data);
    }
    return RA_OK;
}

ra_status_t ra_server_set_error_callback(ra_server_error_callback_t cb,
                                          void* user_data) {
    std::lock_guard lock(g_mu);
    g_err_cb   = cb;
    g_err_user = user_data;
    return RA_OK;
}

}  // extern "C"
