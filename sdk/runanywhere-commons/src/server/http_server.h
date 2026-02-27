/**
 * @file http_server.h
 * @brief Internal HTTP server implementation
 *
 * This is the internal header for the HTTP server implementation.
 * It wraps cpp-httplib and provides the server lifecycle management.
 */

#ifndef RAC_HTTP_SERVER_INTERNAL_H
#define RAC_HTTP_SERVER_INTERNAL_H

#include "rac/server/rac_server.h"
#include "rac/server/rac_openai_types.h"
#include "rac/features/llm/rac_llm_service.h"

#include <httplib.h>
#include <nlohmann/json.hpp>

#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <chrono>

namespace rac {
namespace server {

/**
 * @brief HTTP Server implementation
 *
 * Singleton class that manages the HTTP server lifecycle and
 * routes requests to the appropriate handlers.
 */
class HttpServer {
public:
    /**
     * @brief Get the singleton instance
     */
    static HttpServer& instance();

    /**
     * @brief Start the server with the given configuration
     *
     * @param config Server configuration
     * @return RAC_SUCCESS on success, error code on failure
     */
    rac_result_t start(const rac_server_config_t& config);

    /**
     * @brief Stop the server
     *
     * @return RAC_SUCCESS on success, error code on failure
     */
    rac_result_t stop();

    /**
     * @brief Check if the server is running
     */
    bool isRunning() const;

    /**
     * @brief Get server status
     *
     * @param status Output status structure
     */
    void getStatus(rac_server_status_t& status) const;

    /**
     * @brief Block until the server stops
     *
     * @return Exit code
     */
    int wait();

    /**
     * @brief Set request callback
     */
    void setRequestCallback(rac_server_request_callback_fn callback, void* userData);

    /**
     * @brief Set error callback
     */
    void setErrorCallback(rac_server_error_callback_fn callback, void* userData);

    // Delete copy/move operations (singleton)
    HttpServer(const HttpServer&) = delete;
    HttpServer& operator=(const HttpServer&) = delete;
    HttpServer(HttpServer&&) = delete;
    HttpServer& operator=(HttpServer&&) = delete;

private:
    HttpServer();
    ~HttpServer();

    /**
     * @brief Setup HTTP routes
     */
    void setupRoutes();

    /**
     * @brief Setup CORS middleware
     */
    void setupCors();

    /**
     * @brief Load the LLM model
     */
    rac_result_t loadModel(const std::string& modelPath);

    /**
     * @brief Unload the current model
     */
    void unloadModel();

    /**
     * @brief Server thread function
     */
    void serverThread();

    // Server state
    std::unique_ptr<httplib::Server> server_;
    std::thread serverThread_;
    std::atomic<bool> running_{false};
    std::atomic<bool> shouldStop_{false};
    mutable std::mutex mutex_;
    mutable std::mutex callback_mutex_;  // Protects callback pointers

    // Configuration (copied on start)
    rac_server_config_t config_;
    std::string host_;
    std::string modelPath_;
    std::string modelId_;

    // LLM handle
    rac_handle_t llmHandle_{nullptr};

    // Statistics
    std::atomic<int32_t> activeRequests_{0};
    std::atomic<int64_t> totalRequests_{0};
    std::atomic<int64_t> totalTokensGenerated_{0};
    std::chrono::steady_clock::time_point startTime_;

    // Callbacks
    rac_server_request_callback_fn requestCallback_{nullptr};
    void* requestCallbackUserData_{nullptr};
    rac_server_error_callback_fn errorCallback_{nullptr};
    void* errorCallbackUserData_{nullptr};
};

/**
 * @brief Generate a unique request ID
 */
std::string generateRequestId();

/**
 * @brief Get current Unix timestamp
 */
int64_t getCurrentTimestamp();

/**
 * @brief Extract model ID from file path
 *
 * e.g., "/path/to/llama-3.2-3b-q4.gguf" -> "llama-3.2-3b-q4"
 */
std::string extractModelIdFromPath(const std::string& path);

} // namespace server
} // namespace rac

#endif // RAC_HTTP_SERVER_INTERNAL_H
