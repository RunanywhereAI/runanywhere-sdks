// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — HTTP executor injection C ABI.
//
// On platforms without libcurl (iOS / Android / WASM) the platform bridge
// supplies its own HTTP executor (URLSession / OkHttp / fetch). Frontends
// register the executor once at init; every subsequent C-side HTTP call
// (auth, telemetry, model assignments, …) goes through it.

#ifndef RA_HTTP_H
#define RA_HTTP_H

#include <stddef.h>
#include <stdint.h>

#include "ra_primitives.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t ra_http_method_t;
enum {
    RA_HTTP_GET    = 0,
    RA_HTTP_POST   = 1,
    RA_HTTP_PUT    = 2,
    RA_HTTP_DELETE = 3,
    RA_HTTP_PATCH  = 4,
};

typedef struct {
    const char* name;
    const char* value;
} ra_http_header_t;

typedef struct {
    ra_http_method_t        method;
    const char*             url;
    const ra_http_header_t* headers;
    int32_t                 header_count;
    const uint8_t*          body;
    int32_t                 body_size;
    int32_t                 timeout_ms;     // 0 = default (30s)
} ra_http_request_t;

typedef struct {
    int32_t                  status_code;
    ra_http_header_t*        headers;        // Heap-allocated; may be NULL
    int32_t                  header_count;
    uint8_t*                 body;           // Heap-allocated; may be NULL
    int32_t                  body_size;
    char*                    error_message;  // NULL on success
} ra_http_response_t;

// Executor callback. Synchronous; the platform bridge is responsible for
// running on a background queue if needed and blocking until the response
// is materialised. The frontend allocates the response struct on the heap
// (using malloc) and the core frees it via `ra_http_response_free`.
typedef ra_status_t (*ra_http_executor_t)(const ra_http_request_t* request,
                                           ra_http_response_t*      out_response,
                                           void*                    user_data);

ra_status_t ra_http_set_executor(ra_http_executor_t executor, void* user_data);

uint8_t     ra_http_has_executor(void);

// Internal — invoked by the C++ HttpClient when no libcurl backend is
// available; routes through the registered executor. Returns
// RA_ERR_CAPABILITY_UNSUPPORTED when nothing is registered.
ra_status_t ra_http_execute(const ra_http_request_t* request,
                             ra_http_response_t*      out_response);

// Free a heap response (frees headers + body + error_message).
void ra_http_response_free(ra_http_response_t* response);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_HTTP_H
