/**
 * @file http_client.cpp
 * @brief HTTP client implementation
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "rac/infrastructure/network/rac_http_client.h"

// =============================================================================
// Global State
// =============================================================================

static rac_http_executor_t g_http_executor = nullptr;

// =============================================================================
// Response Management
// =============================================================================

void rac_http_response_free(rac_http_response_t* response) {
    if (!response)
        return;

    free(response->body);
    free(response->error_message);

    if (response->headers) {
        for (size_t i = 0; i < response->header_count; i++) {
            free((void*)response->headers[i].key);
            free((void*)response->headers[i].value);
        }
        free(response->headers);
    }

    memset(response, 0, sizeof(*response));
}

// =============================================================================
// Platform Callback Interface
// =============================================================================

void rac_http_set_executor(rac_http_executor_t executor) {
    g_http_executor = executor;
}

bool rac_http_has_executor(void) {
    return g_http_executor != nullptr;
}

// =============================================================================
// Request Building
// =============================================================================

static char* str_dup(const char* src) {
    if (!src)
        return nullptr;
    size_t len = strlen(src);
    char* dst = (char*)malloc(len + 1);
    if (dst) {
        memcpy(dst, src, len + 1);
    }
    return dst;
}

rac_http_request_t* rac_http_request_create(rac_http_method_t method, const char* url) {
    rac_http_request_t* request = (rac_http_request_t*)calloc(1, sizeof(rac_http_request_t));
    if (!request)
        return nullptr;

    request->method = method;
    request->url = str_dup(url);
    request->timeout_ms = 30000;  // Default 30s timeout

    return request;
}

void rac_http_request_set_body(rac_http_request_t* request, const char* body) {
    if (!request)
        return;

    free((void*)request->body);
    request->body = str_dup(body);
    request->body_length = body ? strlen(body) : 0;
}

void rac_http_request_add_header(rac_http_request_t* request, const char* key, const char* value) {
    if (!request || !key || !value)
        return;

    // Reallocate headers array
    size_t new_count = request->header_count + 1;
    rac_http_header_t* new_headers =
        (rac_http_header_t*)realloc(request->headers, new_count * sizeof(rac_http_header_t));

    if (!new_headers)
        return;

    request->headers = new_headers;
    request->headers[request->header_count].key = str_dup(key);
    request->headers[request->header_count].value = str_dup(value);
    request->header_count = new_count;
}

void rac_http_request_set_timeout(rac_http_request_t* request, int32_t timeout_ms) {
    if (!request)
        return;
    request->timeout_ms = timeout_ms;
}

void rac_http_request_free(rac_http_request_t* request) {
    if (!request)
        return;

    free((void*)request->url);
    free((void*)request->body);

    if (request->headers) {
        for (size_t i = 0; i < request->header_count; i++) {
            free((void*)request->headers[i].key);
            free((void*)request->headers[i].value);
        }
        free(request->headers);
    }

    free(request);
}

// =============================================================================
// Standard Headers
// =============================================================================

void rac_http_add_sdk_headers(rac_http_request_t* request, const char* sdk_version,
                              const char* platform) {
    if (!request)
        return;

    rac_http_request_add_header(request, "Content-Type", "application/json");
    rac_http_request_add_header(request, "X-SDK-Client", "RunAnywhereSDK");

    if (sdk_version) {
        rac_http_request_add_header(request, "X-SDK-Version", sdk_version);
    }
    if (platform) {
        rac_http_request_add_header(request, "X-Platform", platform);
    }

    // Supabase compatibility
    rac_http_request_add_header(request, "Prefer", "return=representation");
}

void rac_http_add_auth_header(rac_http_request_t* request, const char* token) {
    if (!request || !token)
        return;

    char bearer[1024];
    snprintf(bearer, sizeof(bearer), "Bearer %s", token);
    rac_http_request_add_header(request, "Authorization", bearer);
}

void rac_http_add_api_key_header(rac_http_request_t* request, const char* api_key) {
    if (!request || !api_key)
        return;

    // Supabase-style apikey header
    rac_http_request_add_header(request, "apikey", api_key);
}

// =============================================================================
// High-Level Request Functions
// =============================================================================

// Internal callback handler
static void internal_callback(const rac_http_response_t* response, void* user_data) {
    rac_http_context_t* context = (rac_http_context_t*)user_data;
    if (!context)
        return;

    if (response->status_code >= 200 && response->status_code < 300) {
        if (context->on_success) {
            context->on_success(response->body, context->user_data);
        }
    } else {
        if (context->on_error) {
            const char* error_msg = response->error_message
                                        ? response->error_message
                                        : (response->body ? response->body : "Unknown error");
            context->on_error(response->status_code, error_msg, context->user_data);
        }
    }
}

void rac_http_execute(const rac_http_request_t* request, rac_http_context_t* context) {
    if (!request || !context)
        return;

    if (!g_http_executor) {
        if (context->on_error) {
            context->on_error(-1, "HTTP executor not registered", context->user_data);
        }
        return;
    }

    g_http_executor(request, internal_callback, context);
}

void rac_http_post_json(const char* url, const char* json_body, const char* auth_token,
                        rac_http_context_t* context) {
    if (!url || !context)
        return;

    rac_http_request_t* request = rac_http_request_create(RAC_HTTP_POST, url);
    if (!request) {
        if (context->on_error) {
            context->on_error(-1, "Failed to create request", context->user_data);
        }
        return;
    }

    rac_http_request_set_body(request, json_body);
    rac_http_request_add_header(request, "Content-Type", "application/json");

    if (auth_token) {
        rac_http_add_auth_header(request, auth_token);
    }

    rac_http_execute(request, context);
    rac_http_request_free(request);
}

void rac_http_get(const char* url, const char* auth_token, rac_http_context_t* context) {
    if (!url || !context)
        return;

    rac_http_request_t* request = rac_http_request_create(RAC_HTTP_GET, url);
    if (!request) {
        if (context->on_error) {
            context->on_error(-1, "Failed to create request", context->user_data);
        }
        return;
    }

    if (auth_token) {
        rac_http_add_auth_header(request, auth_token);
    }

    rac_http_execute(request, context);
    rac_http_request_free(request);
}
