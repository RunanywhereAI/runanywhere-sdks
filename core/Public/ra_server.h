// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — OpenAI-compatible HTTP server C ABI.
//
// Binds an in-process HTTP server (handler routes /v1/chat/completions,
// /v1/models, etc.) so external tools (LM Studio, llama.cpp clients,
// LangChain, etc.) can talk to a local SDK instance.
//
// Built only when RA_BUILD_SERVER=ON (defaults to OFF on mobile, ON on
// desktop / CLI). Calling these from a build without the server returns
// RA_ERR_CAPABILITY_UNSUPPORTED.

#ifndef RA_SERVER_H
#define RA_SERVER_H

#include <stddef.h>
#include <stdint.h>

#include "ra_primitives.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    const char* host;            // "127.0.0.1" by default
    int32_t     port;            // 0 = auto-pick
    int32_t     max_connections; // 0 = unlimited
    uint8_t     enable_cors;     // 0/1
    uint8_t     _reserved0[3];
    const char* api_key;         // Optional Bearer token
} ra_server_config_t;

typedef int32_t ra_server_state_t;
enum {
    RA_SERVER_STATE_STOPPED = 0,
    RA_SERVER_STATE_STARTING = 1,
    RA_SERVER_STATE_RUNNING  = 2,
    RA_SERVER_STATE_STOPPING = 3,
    RA_SERVER_STATE_FAILED   = 4,
};

typedef struct {
    ra_server_state_t state;
    int32_t           port;
    int64_t           started_at_ms;
    int64_t           total_requests;
} ra_server_status_t;

typedef void (*ra_server_request_callback_t)(const char* method, const char* path,
                                              const char* body, void* user_data);
typedef void (*ra_server_error_callback_t)(ra_status_t code, const char* message,
                                            void* user_data);

ra_status_t ra_server_start(const ra_server_config_t* config);
ra_status_t ra_server_stop(void);
uint8_t     ra_server_is_running(void);
ra_status_t ra_server_get_status(ra_server_status_t* out_status);
ra_status_t ra_server_wait(int32_t timeout_ms);  // -1 = wait forever
ra_status_t ra_server_set_request_callback(ra_server_request_callback_t cb,
                                            void* user_data);
ra_status_t ra_server_set_error_callback(ra_server_error_callback_t cb,
                                          void* user_data);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_SERVER_H
