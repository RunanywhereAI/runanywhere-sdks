/**
 * @file rac_server.h
 * @brief RunAnywhere Commons - OpenAI-Compatible HTTP Server
 *
 * This header defines the public API for the RunAnywhere HTTP server,
 * which provides OpenAI-compatible endpoints for LLM inference.
 *
 * The server exposes:
 *   - GET  /v1/models           - List available models
 *   - POST /v1/chat/completions - Chat completion (streaming & non-streaming)
 *   - GET  /health              - Health check
 *
 * Usage:
 *   1. Configure with rac_server_config_t
 *   2. Call rac_server_start() to start the server
 *   3. Call rac_server_stop() to stop the server
 *
 * Example:
 *   rac_server_config_t config = RAC_SERVER_CONFIG_DEFAULT;
 *   config.model_path = "/path/to/model.gguf";
 *   config.port = 8080;
 *   rac_server_start(&config);
 *   // ... server runs until stop is called ...
 *   rac_server_stop();
 *
 * @see https://platform.openai.com/docs/api-reference/chat
 */

#ifndef RAC_SERVER_H
#define RAC_SERVER_H

#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// SERVER CONFIGURATION
// =============================================================================

/**
 * @brief Server configuration options
 *
 * Configure the HTTP server before starting.
 */
typedef struct rac_server_config {
    /** Host address to bind to (default: "127.0.0.1") */
    const char* host;

    /** Port to listen on (default: 8080) */
    uint16_t port;

    /** Path to the GGUF model file (required) */
    const char* model_path;

    /** Model ID to expose via /v1/models (default: derived from filename) */
    const char* model_id;

    /** Context window size in tokens (default: 8192) */
    int32_t context_size;

    /** Number of threads for inference (default: 4, 0 = auto) */
    int32_t threads;

    /** Number of GPU layers to offload (default: 0 = CPU only) */
    int32_t gpu_layers;

    /** Enable CORS headers for browser access (default: true) */
    rac_bool_t enable_cors;

    /** CORS allowed origins (default: "*") */
    const char* cors_origins;

    /** Request timeout in seconds (default: 300 = 5 minutes) */
    int32_t request_timeout_seconds;

    /** Maximum concurrent requests (default: 4) */
    int32_t max_concurrent_requests;

    /** Verbose logging (default: false) */
    rac_bool_t verbose;
} rac_server_config_t;

/**
 * @brief Default server configuration
 */
static const rac_server_config_t RAC_SERVER_CONFIG_DEFAULT = {
    .host = "127.0.0.1",
    .port = 8080,
    .model_path = RAC_NULL,
    .model_id = RAC_NULL,
    .context_size = 8192,
    .threads = 4,
    .gpu_layers = 0,
    .enable_cors = RAC_TRUE,
    .cors_origins = "*",
    .request_timeout_seconds = 300,
    .max_concurrent_requests = 4,
    .verbose = RAC_FALSE
};

// =============================================================================
// SERVER STATUS
// =============================================================================

/**
 * @brief Server status information
 */
typedef struct rac_server_status {
    /** Whether the server is currently running */
    rac_bool_t is_running;

    /** Host the server is bound to */
    const char* host;

    /** Port the server is listening on */
    uint16_t port;

    /** Currently loaded model ID */
    const char* model_id;

    /** Number of requests currently being processed */
    int32_t active_requests;

    /** Total requests handled since start */
    int64_t total_requests;

    /** Total tokens generated since start */
    int64_t total_tokens_generated;

    /** Server uptime in seconds */
    int64_t uptime_seconds;
} rac_server_status_t;

// =============================================================================
// SERVER LIFECYCLE
// =============================================================================

/**
 * @brief Start the HTTP server
 *
 * Starts the server in a background thread. The function returns immediately
 * after the server is ready to accept connections.
 *
 * @param config Server configuration (model_path is required)
 * @return RAC_SUCCESS on success, error code on failure
 *
 * Error codes:
 *   - RAC_ERROR_INVALID_ARGUMENT: config is NULL or model_path is NULL
 *   - RAC_ERROR_ALREADY_RUNNING: Server is already running
 *   - RAC_ERROR_MODEL_NOT_FOUND: Model file not found
 *   - RAC_ERROR_MODEL_LOAD_FAILED: Failed to load model
 *   - RAC_ERROR_BIND_FAILED: Failed to bind to port
 */
RAC_API rac_result_t rac_server_start(const rac_server_config_t* config);

/**
 * @brief Stop the HTTP server
 *
 * Gracefully stops the server, waiting for active requests to complete
 * (up to a timeout).
 *
 * @return RAC_SUCCESS on success, RAC_ERROR_NOT_RUNNING if not running
 */
RAC_API rac_result_t rac_server_stop(void);

/**
 * @brief Check if the server is running
 *
 * @return RAC_TRUE if running, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_server_is_running(void);

/**
 * @brief Get server status
 *
 * @param status Output parameter for status (must not be NULL)
 * @return RAC_SUCCESS on success
 */
RAC_API rac_result_t rac_server_get_status(rac_server_status_t* status);

/**
 * @brief Block until the server stops
 *
 * Useful for main() to keep the process alive while serving requests.
 * Returns when rac_server_stop() is called or on error.
 *
 * @return Exit code (0 on clean shutdown)
 */
RAC_API int rac_server_wait(void);

// =============================================================================
// SERVER CALLBACKS (Optional)
// =============================================================================

/**
 * @brief Request callback type
 *
 * Called for each incoming request (before processing).
 *
 * @param method HTTP method (e.g., "GET", "POST")
 * @param path Request path (e.g., "/v1/chat/completions")
 * @param user_data User-provided context
 */
typedef void (*rac_server_request_callback_fn)(const char* method,
                                                const char* path,
                                                void* user_data);

/**
 * @brief Set request callback
 *
 * @param callback Callback function (NULL to disable)
 * @param user_data Context passed to callback
 */
RAC_API void rac_server_set_request_callback(rac_server_request_callback_fn callback,
                                              void* user_data);

/**
 * @brief Error callback type
 *
 * Called when an error occurs during request processing.
 *
 * @param path Request path
 * @param error_code Error code
 * @param error_message Human-readable error message
 * @param user_data User-provided context
 */
typedef void (*rac_server_error_callback_fn)(const char* path,
                                              rac_result_t error_code,
                                              const char* error_message,
                                              void* user_data);

/**
 * @brief Set error callback
 *
 * @param callback Callback function (NULL to disable)
 * @param user_data Context passed to callback
 */
RAC_API void rac_server_set_error_callback(rac_server_error_callback_fn callback,
                                            void* user_data);

// =============================================================================
// ERROR CODES
// =============================================================================

/** Server is already running */
#define RAC_ERROR_SERVER_ALREADY_RUNNING ((rac_result_t)-200)

/** Server is not running */
#define RAC_ERROR_SERVER_NOT_RUNNING ((rac_result_t)-201)

/** Failed to bind to port */
#define RAC_ERROR_SERVER_BIND_FAILED ((rac_result_t)-202)

/** Model file not found */
#define RAC_ERROR_SERVER_MODEL_NOT_FOUND ((rac_result_t)-203)

/** Failed to load model */
#define RAC_ERROR_SERVER_MODEL_LOAD_FAILED ((rac_result_t)-204)

/** Request timeout */
#define RAC_ERROR_SERVER_REQUEST_TIMEOUT ((rac_result_t)-205)

/** Too many concurrent requests */
#define RAC_ERROR_SERVER_TOO_MANY_REQUESTS ((rac_result_t)-206)

#ifdef __cplusplus
}
#endif

#endif /* RAC_SERVER_H */
