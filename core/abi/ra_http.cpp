// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_http.h"

#include <atomic>
#include <cstdlib>
#include <cstring>
#include <mutex>

namespace {
std::mutex          g_mu;
ra_http_executor_t  g_executor = nullptr;
void*               g_user     = nullptr;
}  // namespace

extern "C" {

ra_status_t ra_http_set_executor(ra_http_executor_t executor, void* user_data) {
    std::lock_guard lock(g_mu);
    g_executor = executor;
    g_user     = user_data;
    return RA_OK;
}

uint8_t ra_http_has_executor(void) {
    std::lock_guard lock(g_mu);
    return g_executor != nullptr ? 1 : 0;
}

ra_status_t ra_http_execute(const ra_http_request_t* request,
                             ra_http_response_t*      out_response) {
    if (!request || !out_response) return RA_ERR_INVALID_ARGUMENT;
    ra_http_executor_t cb;
    void*              user;
    {
        std::lock_guard lock(g_mu);
        cb   = g_executor;
        user = g_user;
    }
    if (!cb) return RA_ERR_CAPABILITY_UNSUPPORTED;
    return cb(request, out_response, user);
}

void ra_http_response_free(ra_http_response_t* response) {
    if (!response) return;
    if (response->headers) {
        for (int32_t i = 0; i < response->header_count; ++i) {
            std::free((void*)response->headers[i].name);
            std::free((void*)response->headers[i].value);
        }
        std::free(response->headers);
    }
    if (response->body)          std::free(response->body);
    if (response->error_message) std::free(response->error_message);
    *response = ra_http_response_t{};
}

}  // extern "C"
