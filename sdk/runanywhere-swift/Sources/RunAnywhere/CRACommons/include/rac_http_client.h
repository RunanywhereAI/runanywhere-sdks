/**
 * @file rac_http_client.h
 * @brief HTTP client abstraction
 *
 * Defines a platform-agnostic HTTP interface. Platform SDKs implement
 * the actual HTTP transport (URLSession, OkHttp, etc.) and register
 * it via callback.
 */

#ifndef RAC_HTTP_CLIENT_H
#define RAC_HTTP_CLIENT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// HTTP Types
// =============================================================================

/**
 * @brief HTTP method enum
 */
typedef enum {
    RAC_HTTP_GET = 0,
    RAC_HTTP_POST = 1,
    RAC_HTTP_PUT = 2,
    RAC_HTTP_DELETE = 3,
    RAC_HTTP_PATCH = 4
} rac_http_method_t;

/**
 * @brief HTTP header key-value pair
 */
typedef struct {
    const char* key;
    const char* value;
} rac_http_header_t;

/**
 * @brief HTTP request structure
 */
typedef struct {
    rac_http_method_t method;
    const char* url;   // Full URL
    const char* body;  // JSON body (can be NULL for GET)
    size_t body_length;
    rac_http_header_t* headers;
    size_t header_count;
    int32_t timeout_ms;  // Request timeout in milliseconds
} rac_http_request_t;

/**
 * @brief HTTP response structure
 */
typedef struct {
    int32_t status_code;  // HTTP status code (200, 401, etc.)
    char* body;           // Response body (caller frees)
    size_t body_length;
    rac_http_header_t* headers;
    size_t header_count;
    char* error_message;  // Non-HTTP error (network failure, etc.)
} rac_http_response_t;

// =============================================================================
// Response Memory Management
// =============================================================================

/**
 * @brief Free HTTP response
 */
void rac_http_response_free(rac_http_response_t* response);

// =============================================================================
// Platform Callback Interface
// =============================================================================

/**
 * @brief Callback type for receiving HTTP response
 *
 * @param response The HTTP response (platform must free after callback returns)
 * @param user_data Opaque user data passed to request
 */
typedef void (*rac_http_callback_t)(const rac_http_response_t* response, void* user_data);

/**
 * @brief HTTP executor function type
 *
 * Platform implements this to perform actual HTTP requests.
 * Must call callback when request completes (success or failure).
 *
 * @param request The HTTP request to execute
 * @param callback Callback to invoke with response
 * @param user_data Opaque user data to pass to callback
 */
typedef void (*rac_http_executor_t)(const rac_http_request_t* request, rac_http_callback_t callback,
                                    void* user_data);

/**
 * @brief Register platform HTTP executor
 *
 * Platform SDKs must call this during initialization to provide
 * their HTTP implementation.
 *
 * @param executor The executor function
 */
void rac_http_set_executor(rac_http_executor_t executor);

/**
 * @brief Check if HTTP executor is registered
 * @return true if executor has been set
 */
bool rac_http_has_executor(void);

// =============================================================================
// Request Building Helpers
// =============================================================================

/**
 * @brief Create a new HTTP request
 * @param method HTTP method
 * @param url Full URL
 * @return New request (caller must free with rac_http_request_free)
 */
rac_http_request_t* rac_http_request_create(rac_http_method_t method, const char* url);

/**
 * @brief Set request body
 * @param request The request
 * @param body JSON body string
 */
void rac_http_request_set_body(rac_http_request_t* request, const char* body);

/**
 * @brief Add header to request
 * @param request The request
 * @param key Header key
 * @param value Header value
 */
void rac_http_request_add_header(rac_http_request_t* request, const char* key, const char* value);

/**
 * @brief Set request timeout
 * @param request The request
 * @param timeout_ms Timeout in milliseconds
 */
void rac_http_request_set_timeout(rac_http_request_t* request, int32_t timeout_ms);

/**
 * @brief Free HTTP request
 */
void rac_http_request_free(rac_http_request_t* request);

// =============================================================================
// Standard Headers
// =============================================================================

/**
 * @brief Add standard SDK headers to request
 *
 * Adds: Content-Type, X-SDK-Client, X-SDK-Version, X-Platform
 *
 * @param request The request
 * @param sdk_version SDK version string
 * @param platform Platform string
 */
void rac_http_add_sdk_headers(rac_http_request_t* request, const char* sdk_version,
                              const char* platform);

/**
 * @brief Add authorization header
 * @param request The request
 * @param token Bearer token
 */
void rac_http_add_auth_header(rac_http_request_t* request, const char* token);

/**
 * @brief Add API key header (for Supabase compatibility)
 * @param request The request
 * @param api_key API key
 */
void rac_http_add_api_key_header(rac_http_request_t* request, const char* api_key);

// =============================================================================
// High-Level Request Functions
// =============================================================================

/**
 * @brief Context for async HTTP operations
 */
typedef struct {
    void* user_data;
    void (*on_success)(const char* response_body, void* user_data);
    void (*on_error)(int status_code, const char* error_message, void* user_data);
} rac_http_context_t;

/**
 * @brief Execute HTTP request asynchronously
 *
 * Uses the registered platform executor.
 *
 * @param request The request to execute
 * @param context Callback context
 */
void rac_http_execute(const rac_http_request_t* request, rac_http_context_t* context);

/**
 * @brief Helper: POST JSON to endpoint
 * @param url Full URL
 * @param json_body JSON body
 * @param auth_token Bearer token (can be NULL)
 * @param context Callback context
 */
void rac_http_post_json(const char* url, const char* json_body, const char* auth_token,
                        rac_http_context_t* context);

/**
 * @brief Helper: GET from endpoint
 * @param url Full URL
 * @param auth_token Bearer token (can be NULL)
 * @param context Callback context
 */
void rac_http_get(const char* url, const char* auth_token, rac_http_context_t* context);

#ifdef __cplusplus
}
#endif

#endif  // RAC_HTTP_CLIENT_H
