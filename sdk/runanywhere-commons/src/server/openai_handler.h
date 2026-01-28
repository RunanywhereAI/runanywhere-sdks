/**
 * @file openai_handler.h
 * @brief OpenAI API endpoint handlers
 *
 * Handles the OpenAI-compatible HTTP endpoints:
 *   - GET  /v1/models
 *   - POST /v1/chat/completions
 *   - GET  /health
 */

#ifndef RAC_OPENAI_HANDLER_H
#define RAC_OPENAI_HANDLER_H

#include "rac/server/rac_openai_types.h"
#include "rac/features/llm/rac_llm_service.h"

#include <httplib.h>
#include <nlohmann/json.hpp>

#include <string>
#include <atomic>

namespace rac {
namespace server {

/**
 * @brief OpenAI API request handler
 *
 * Handles incoming HTTP requests and translates them to/from
 * the RunAnywhere LLM service.
 */
class OpenAIHandler {
public:
    /**
     * @brief Construct handler with LLM handle
     *
     * @param llmHandle LLM service handle (must remain valid)
     * @param modelId Model ID to report
     */
    OpenAIHandler(rac_handle_t llmHandle, const std::string& modelId);

    /**
     * @brief Handle GET /v1/models
     */
    void handleModels(const httplib::Request& req, httplib::Response& res);

    /**
     * @brief Handle POST /v1/chat/completions
     */
    void handleChatCompletions(const httplib::Request& req, httplib::Response& res);

    /**
     * @brief Handle GET /health
     */
    void handleHealth(const httplib::Request& req, httplib::Response& res);

    /**
     * @brief Get total tokens generated
     */
    int64_t getTotalTokensGenerated() const { return totalTokensGenerated_.load(); }

private:
    /**
     * @brief Process a non-streaming chat completion request
     */
    void processNonStreaming(const httplib::Request& req,
                             httplib::Response& res,
                             const nlohmann::json& requestJson);

    /**
     * @brief Process a streaming chat completion request
     */
    void processStreaming(const httplib::Request& req,
                          httplib::Response& res,
                          const nlohmann::json& requestJson);

    /**
     * @brief Parse generation options from request
     */
    rac_llm_options_t parseOptions(const nlohmann::json& requestJson);

    /**
     * @brief Send an error response
     */
    void sendError(httplib::Response& res, int statusCode,
                   const std::string& message, const std::string& type);

    rac_handle_t llmHandle_;
    std::string modelId_;
    std::atomic<int64_t> totalTokensGenerated_{0};
};

} // namespace server
} // namespace rac

#endif // RAC_OPENAI_HANDLER_H
