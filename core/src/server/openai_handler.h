/** @file openai_handler.h OpenAI-compatible endpoints for one loaded LLM. */
#ifndef RAC_OPENAI_HANDLER_H
#define RAC_OPENAI_HANDLER_H

#include <httplib.h>

#include <atomic>
#include <mutex>
#include <nlohmann/json.hpp>
#include <string>

#include "rac/features/llm/rac_llm_service.h"

namespace rac::server {

class OpenAIHandler {
   public:
    OpenAIHandler(rac_handle_t llmHandle, const std::string& modelId, int32_t threads = 0,
                  int32_t timeoutSeconds = 300);
    void handleModels(const httplib::Request& req, httplib::Response& res);
    void handleChatCompletions(const httplib::Request& req, httplib::Response& res);
    void handleHealth(const httplib::Request& req, httplib::Response& res);
    void requestStop();
    int64_t getTotalTokensGenerated() const { return totalTokensGenerated_.load(); }
    int32_t getActiveRequests() const { return activeRequests_.load(); }

   private:
    void processNonStreaming(const httplib::Request& req, httplib::Response& res,
                             const nlohmann::json& request);
    void processStreaming(const httplib::Request& req, httplib::Response& res,
                          const nlohmann::json& request);
    static void sendError(httplib::Response& res, int status, const std::string& message,
                          const std::string& type);

    rac_handle_t llmHandle_;
    std::string modelId_;
    int32_t threads_;
    int32_t timeoutSeconds_;
    bool ready_;
    // One backend session owns one KV cache. Hold this through the SSE provider,
    // whose invocation happens AFTER the route handler has returned.
    std::mutex generationMutex_;
    std::atomic<bool> stopping_{false};
    std::atomic<int32_t> activeRequests_{0};
    std::atomic<int64_t> totalTokensGenerated_{0};
};

}  // namespace rac::server
#endif
