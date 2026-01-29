/**
 * @file http_server.cpp
 * @brief HTTP server implementation
 */

#include "http_server.h"
#include "openai_handler.h"
#include "rac/core/rac_logger.h"
#include "rac/backends/rac_llm_llamacpp.h"

#include <filesystem>
#include <algorithm>

namespace rac {
namespace server {

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

std::string generateRequestId() {
    static std::atomic<uint64_t> counter{0};
    std::ostringstream ss;
    ss << "req-" << std::hex << std::chrono::steady_clock::now().time_since_epoch().count()
       << "-" << counter++;
    return ss.str();
}

int64_t getCurrentTimestamp() {
    return std::chrono::duration_cast<std::chrono::seconds>(
        std::chrono::system_clock::now().time_since_epoch()
    ).count();
}

std::string extractModelIdFromPath(const std::string& path) {
    std::filesystem::path fsPath(path);
    std::string filename = fsPath.stem().string();

    // Remove common extensions like .gguf
    if (fsPath.extension() == ".gguf") {
        // Already handled by stem()
    }

    // Clean up the name
    return filename;
}

// =============================================================================
// HTTP SERVER IMPLEMENTATION
// =============================================================================

HttpServer& HttpServer::instance() {
    static HttpServer instance;
    return instance;
}

HttpServer::HttpServer() = default;

HttpServer::~HttpServer() {
    if (running_) {
        stop();
    }
}

rac_result_t HttpServer::start(const rac_server_config_t& config) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (running_) {
        return RAC_ERROR_SERVER_ALREADY_RUNNING;
    }

    // Validate config
    if (!config.model_path) {
        RAC_LOG_ERROR("Server", "model_path is required");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Check if model file exists
    if (!std::filesystem::exists(config.model_path)) {
        RAC_LOG_ERROR("Server", "Model file not found: %s", config.model_path);
        return RAC_ERROR_SERVER_MODEL_NOT_FOUND;
    }

    // Copy configuration
    config_ = config;
    host_ = config.host ? config.host : "127.0.0.1";
    modelPath_ = config.model_path;
    modelId_ = config.model_id ? config.model_id : extractModelIdFromPath(modelPath_);

    // Load the model
    rac_result_t rc = loadModel(modelPath_);
    if (RAC_FAILED(rc)) {
        return rc;
    }

    // Create HTTP server
    server_ = std::make_unique<httplib::Server>();

    // Setup CORS if enabled
    if (config.enable_cors == RAC_TRUE) {
        setupCors();
    }

    // Setup routes
    setupRoutes();

    // Reset state
    shouldStop_ = false;
    activeRequests_ = 0;
    totalRequests_ = 0;
    totalTokensGenerated_ = 0;
    startTime_ = std::chrono::steady_clock::now();

    // Start server thread
    serverThread_ = std::thread(&HttpServer::serverThread, this);

    // Wait for server to be ready (with timeout)
    for (int i = 0; i < 100; ++i) {  // 10 second timeout
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        if (running_) {
            RAC_LOG_INFO("Server", "RunAnywhere Server started on http://%s:%d",
                         host_.c_str(), config_.port);
            RAC_LOG_INFO("Server", "Model: %s", modelId_.c_str());
            return RAC_SUCCESS;
        }
    }

    // Timeout - something went wrong
    shouldStop_ = true;
    if (serverThread_.joinable()) {
        serverThread_.join();
    }
    unloadModel();

    RAC_LOG_ERROR("Server", "Failed to start server");
    return RAC_ERROR_SERVER_BIND_FAILED;
}

rac_result_t HttpServer::stop() {
    std::lock_guard<std::mutex> lock(mutex_);

    if (!running_) {
        return RAC_ERROR_SERVER_NOT_RUNNING;
    }

    RAC_LOG_INFO("Server", "Stopping server...");

    shouldStop_ = true;

    if (server_) {
        server_->stop();
    }

    if (serverThread_.joinable()) {
        serverThread_.join();
    }

    unloadModel();

    server_.reset();
    running_ = false;

    RAC_LOG_INFO("Server", "Server stopped");

    return RAC_SUCCESS;
}

bool HttpServer::isRunning() const {
    return running_;
}

void HttpServer::getStatus(rac_server_status_t& status) const {
    std::lock_guard<std::mutex> lock(mutex_);

    status.is_running = running_ ? RAC_TRUE : RAC_FALSE;
    status.host = host_.c_str();
    status.port = config_.port;
    status.model_id = modelId_.c_str();
    status.active_requests = activeRequests_;
    status.total_requests = totalRequests_;
    status.total_tokens_generated = totalTokensGenerated_;

    if (running_) {
        auto now = std::chrono::steady_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::seconds>(now - startTime_);
        status.uptime_seconds = duration.count();
    } else {
        status.uptime_seconds = 0;
    }
}

int HttpServer::wait() {
    if (serverThread_.joinable()) {
        serverThread_.join();
    }
    return 0;
}

void HttpServer::setRequestCallback(rac_server_request_callback_fn callback, void* userData) {
    requestCallback_ = callback;
    requestCallbackUserData_ = userData;
}

void HttpServer::setErrorCallback(rac_server_error_callback_fn callback, void* userData) {
    errorCallback_ = callback;
    errorCallbackUserData_ = userData;
}

void HttpServer::setupRoutes() {
    // Create handler with LLM handle
    auto handler = std::make_shared<OpenAIHandler>(llmHandle_, modelId_);

    // GET /v1/models
    server_->Get("/v1/models", [this, handler](const httplib::Request& req, httplib::Response& res) {
        totalRequests_++;
        if (requestCallback_) {
            requestCallback_("GET", "/v1/models", requestCallbackUserData_);
        }
        handler->handleModels(req, res);
    });

    // POST /v1/chat/completions
    server_->Post("/v1/chat/completions", [this, handler](const httplib::Request& req, httplib::Response& res) {
        totalRequests_++;
        activeRequests_++;

        if (requestCallback_) {
            requestCallback_("POST", "/v1/chat/completions", requestCallbackUserData_);
        }

        try {
            handler->handleChatCompletions(req, res);
        } catch (const std::exception& e) {
            RAC_LOG_ERROR("Server", "Error handling chat completions: %s", e.what());
            if (errorCallback_) {
                errorCallback_("/v1/chat/completions", RAC_ERROR_UNKNOWN, e.what(), errorCallbackUserData_);
            }
            res.status = 500;
            res.set_content("{\"error\": {\"message\": \"Internal server error\"}}", "application/json");
        }

        activeRequests_--;
    });

    // GET /health
    server_->Get("/health", [this, handler](const httplib::Request& req, httplib::Response& res) {
        totalRequests_++;
        handler->handleHealth(req, res);
    });

    // Root endpoint - info
    server_->Get("/", [this](const httplib::Request& /*req*/, httplib::Response& res) {
        nlohmann::json info;
        info["name"] = "RunAnywhere Server";
        info["version"] = "1.0.0";
        info["model"] = modelId_;
        info["endpoints"] = {
            "GET  /v1/models",
            "POST /v1/chat/completions",
            "GET  /health"
        };
        res.set_content(info.dump(2), "application/json");
    });
}

void HttpServer::setupCors() {
    std::string origins = config_.cors_origins ? config_.cors_origins : "*";

    server_->set_pre_routing_handler([origins](const httplib::Request& req, httplib::Response& res) {
        res.set_header("Access-Control-Allow-Origin", origins);
        res.set_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
        res.set_header("Access-Control-Allow-Headers", "Content-Type, Authorization");

        // Handle preflight
        if (req.method == "OPTIONS") {
            res.status = 204;
            return httplib::Server::HandlerResponse::Handled;
        }

        return httplib::Server::HandlerResponse::Unhandled;
    });
}

rac_result_t HttpServer::loadModel(const std::string& modelPath) {
    RAC_LOG_INFO("Server", "Loading model: %s", modelPath.c_str());

#ifdef RAC_HAS_LLAMACPP
    // Register LlamaCPP backend if not already registered
    rac_backend_llamacpp_register();

    // Create LLM handle using model path as ID
    rac_result_t rc = rac_llm_create(modelPath.c_str(), &llmHandle_);
    if (RAC_FAILED(rc)) {
        RAC_LOG_ERROR("Server", "Failed to create LLM handle: %d", rc);
        return RAC_ERROR_SERVER_MODEL_LOAD_FAILED;
    }

    // Initialize with the model path
    rc = rac_llm_initialize(llmHandle_, modelPath.c_str());
    if (RAC_FAILED(rc)) {
        RAC_LOG_ERROR("Server", "Failed to initialize LLM: %d", rc);
        rac_llm_destroy(llmHandle_);
        llmHandle_ = nullptr;
        return RAC_ERROR_SERVER_MODEL_LOAD_FAILED;
    }

    RAC_LOG_INFO("Server", "Model loaded successfully");
    return RAC_SUCCESS;
#else
    RAC_LOG_ERROR("Server", "LlamaCPP backend not available");
    return RAC_ERROR_SERVER_MODEL_LOAD_FAILED;
#endif
}

void HttpServer::unloadModel() {
    if (llmHandle_) {
        rac_llm_destroy(llmHandle_);
        llmHandle_ = nullptr;
    }
}

void HttpServer::serverThread() {
    RAC_LOG_DEBUG("Server", "Server thread starting on %s:%d", host_.c_str(), config_.port);

    // Mark as running before listen() to signal startup
    running_ = true;

    // Listen (blocking)
    if (!server_->listen(host_.c_str(), config_.port)) {
        if (!shouldStop_) {
            RAC_LOG_ERROR("Server", "Failed to bind to %s:%d", host_.c_str(), config_.port);
        }
    }

    running_ = false;
    RAC_LOG_DEBUG("Server", "Server thread exiting");
}

} // namespace server
} // namespace rac

// =============================================================================
// C API IMPLEMENTATION
// =============================================================================

extern "C" {

RAC_API rac_result_t rac_server_start(const rac_server_config_t* config) {
    if (!config) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    return rac::server::HttpServer::instance().start(*config);
}

RAC_API rac_result_t rac_server_stop(void) {
    return rac::server::HttpServer::instance().stop();
}

RAC_API rac_bool_t rac_server_is_running(void) {
    return rac::server::HttpServer::instance().isRunning() ? RAC_TRUE : RAC_FALSE;
}

RAC_API rac_result_t rac_server_get_status(rac_server_status_t* status) {
    if (!status) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    rac::server::HttpServer::instance().getStatus(*status);
    return RAC_SUCCESS;
}

RAC_API int rac_server_wait(void) {
    return rac::server::HttpServer::instance().wait();
}

RAC_API void rac_server_set_request_callback(rac_server_request_callback_fn callback,
                                              void* user_data) {
    rac::server::HttpServer::instance().setRequestCallback(callback, user_data);
}

RAC_API void rac_server_set_error_callback(rac_server_error_callback_fn callback,
                                            void* user_data) {
    rac::server::HttpServer::instance().setErrorCallback(callback, user_data);
}

// Memory management for OpenAI types
RAC_API void rac_openai_chat_response_free(rac_openai_chat_response_t* response) {
    if (!response) return;

    if (response->id) {
        rac_free(response->id);
        response->id = nullptr;
    }

    if (response->choices) {
        for (size_t i = 0; i < response->num_choices; ++i) {
            auto& choice = response->choices[i];
            if (choice.message.content) {
                rac_free(choice.message.content);
            }
            if (choice.message.tool_calls) {
                for (size_t j = 0; j < choice.message.num_tool_calls; ++j) {
                    auto& tc = choice.message.tool_calls[j];
                    if (tc.id) rac_free(const_cast<char*>(tc.id));
                    if (tc.function_name) rac_free(const_cast<char*>(tc.function_name));
                    if (tc.function_arguments) rac_free(const_cast<char*>(tc.function_arguments));
                }
                rac_free(choice.message.tool_calls);
            }
        }
        rac_free(response->choices);
        response->choices = nullptr;
    }
}

RAC_API void rac_openai_models_response_free(rac_openai_models_response_t* response) {
    if (!response) return;

    if (response->data) {
        rac_free(response->data);
        response->data = nullptr;
    }
}

} // extern "C"
