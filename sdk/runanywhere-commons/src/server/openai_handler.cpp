/**
 * @file openai_handler.cpp
 * @brief OpenAI API endpoint handlers implementation
 */

#include "openai_handler.h"
#include "json_utils.h"
#include "rac/core/rac_logger.h"

#include <chrono>
#include <sstream>
#include <random>

namespace rac {
namespace server {

namespace {

// Generate a random ID for requests
std::string generateId(const std::string& prefix) {
    static std::random_device rd;
    static std::mt19937 gen(rd());
    static std::uniform_int_distribution<uint64_t> dis;

    std::ostringstream ss;
    ss << prefix << std::hex << dis(gen);
    return ss.str();
}

// Get current Unix timestamp
int64_t currentTimestamp() {
    return std::chrono::duration_cast<std::chrono::seconds>(
        std::chrono::system_clock::now().time_since_epoch()
    ).count();
}

} // anonymous namespace

OpenAIHandler::OpenAIHandler(rac_handle_t llmHandle, const std::string& modelId)
    : llmHandle_(llmHandle)
    , modelId_(modelId)
{
}

void OpenAIHandler::handleModels(const httplib::Request& /*req*/, httplib::Response& res) {
    rac_openai_models_response_t response = {};
    response.object = "list";

    rac_openai_model_t model = {};
    model.id = modelId_.c_str();
    model.object = "model";
    model.created = currentTimestamp();
    model.owned_by = "runanywhere";

    response.data = &model;
    response.num_data = 1;

    auto jsonResponse = json::serializeModelsResponse(response);

    res.set_content(jsonResponse.dump(), "application/json");
    res.status = 200;
}

void OpenAIHandler::handleChatCompletions(const httplib::Request& req, httplib::Response& res) {
    // Parse request body
    nlohmann::json requestJson;
    try {
        requestJson = nlohmann::json::parse(req.body);
    } catch (const std::exception& e) {
        sendError(res, 400, std::string("Invalid JSON: ") + e.what(), "invalid_request_error");
        return;
    }

    // Check for required fields
    if (!requestJson.contains("messages") || !requestJson["messages"].is_array()) {
        sendError(res, 400, "Missing required field: messages", "invalid_request_error");
        return;
    }

    if (requestJson["messages"].empty()) {
        sendError(res, 400, "messages array cannot be empty", "invalid_request_error");
        return;
    }

    // Check if streaming is requested
    bool stream = false;
    if (requestJson.contains("stream") && requestJson["stream"].is_boolean()) {
        stream = requestJson["stream"].get<bool>();
    }

    if (stream) {
        processStreaming(req, res, requestJson);
    } else {
        processNonStreaming(req, res, requestJson);
    }
}

void OpenAIHandler::handleHealth(const httplib::Request& /*req*/, httplib::Response& res) {
    nlohmann::json response;
    response["status"] = "ok";
    response["model"] = modelId_;

    // Check if LLM is ready
    rac_llm_info_t info = {};
    if (llmHandle_ && rac_llm_get_info(llmHandle_, &info) == RAC_SUCCESS) {
        response["model_loaded"] = info.is_ready == RAC_TRUE;
    } else {
        response["model_loaded"] = false;
    }

    res.set_content(response.dump(), "application/json");
    res.status = 200;
}

void OpenAIHandler::processNonStreaming(const httplib::Request& /*req*/,
                                         httplib::Response& res,
                                         const nlohmann::json& requestJson) {
    // Build prompt from messages
    std::string prompt = buildPromptFromRequest(requestJson);

    // Parse options
    rac_llm_options_t options = parseOptions(requestJson);

    // Generate response
    rac_llm_result_t result = {};
    rac_result_t rc = rac_llm_generate(llmHandle_, prompt.c_str(), &options, &result);

    if (RAC_FAILED(rc)) {
        sendError(res, 500, "Generation failed", "server_error");
        return;
    }

    // Update token count
    totalTokensGenerated_ += result.completion_tokens;

    // Build response
    std::string requestId = generateId("chatcmpl-");

    rac_openai_chat_response_t response = {};
    response.id = const_cast<char*>(requestId.c_str());
    response.object = "chat.completion";
    response.created = currentTimestamp();
    response.model = modelId_.c_str();

    rac_openai_assistant_message_t message = {};
    message.role = RAC_OPENAI_ROLE_ASSISTANT;
    message.content = result.text;
    message.tool_calls = nullptr;
    message.num_tool_calls = 0;

    rac_openai_choice_t choice = {};
    choice.index = 0;
    choice.message = message;
    choice.finish_reason = RAC_OPENAI_FINISH_STOP;

    response.choices = &choice;
    response.num_choices = 1;

    response.usage.prompt_tokens = result.prompt_tokens;
    response.usage.completion_tokens = result.completion_tokens;
    response.usage.total_tokens = result.total_tokens;

    auto jsonResponse = json::serializeChatResponse(response);

    // Clean up
    rac_llm_result_free(&result);

    res.set_content(jsonResponse.dump(), "application/json");
    res.status = 200;
}

void OpenAIHandler::processStreaming(const httplib::Request& /*req*/,
                                      httplib::Response& res,
                                      const nlohmann::json& requestJson) {
    // Build prompt from messages
    std::string prompt = buildPromptFromRequest(requestJson);

    // Parse options
    rac_llm_options_t options = parseOptions(requestJson);
    options.streaming_enabled = RAC_TRUE;

    // Generate request ID
    std::string requestId = generateId("chatcmpl-");
    int64_t created = currentTimestamp();

    // Set up streaming response
    res.set_header("Content-Type", "text/event-stream");
    res.set_header("Cache-Control", "no-cache");
    res.set_header("Connection", "keep-alive");

    // Track token count
    std::atomic<int32_t> tokenCount{0};

    // Streaming callback
    struct CallbackData {
        httplib::Response* res;
        std::string* requestId;
        std::string* modelId;
        int64_t created;
        std::atomic<int32_t>* tokenCount;
        bool firstToken;
    };

    CallbackData cbData = {
        &res,
        &requestId,
        &modelId_,
        created,
        &tokenCount,
        true
    };

    // Start streaming
    res.set_content_provider(
        "text/event-stream",
        [this, prompt, options, cbData](size_t /*offset*/, httplib::DataSink& sink) mutable {
            // First chunk: send role
            if (cbData.firstToken) {
                rac_openai_stream_chunk_t chunk = {};
                chunk.id = cbData.requestId->c_str();
                chunk.object = "chat.completion.chunk";
                chunk.created = cbData.created;
                chunk.model = cbData.modelId->c_str();

                rac_openai_delta_t delta = {};
                delta.role = "assistant";
                delta.content = nullptr;

                rac_openai_stream_choice_t choice = {};
                choice.index = 0;
                choice.delta = delta;
                choice.finish_reason = RAC_OPENAI_FINISH_NONE;

                chunk.choices = &choice;
                chunk.num_choices = 1;

                std::string sseData = json::formatSSE(json::serializeStreamChunk(chunk));
                sink.write(sseData.c_str(), sseData.size());

                cbData.firstToken = false;
            }

            // Generate with streaming callback
            rac_llm_stream_params_t params = {};
            params.prompt = prompt.c_str();
            params.options = options;
            params.user_data = &sink;
            params.on_token = [](const char* token, void* userData) -> rac_bool_t {
                auto* sinkPtr = static_cast<httplib::DataSink*>(userData);

                // We can't easily access the full context here, so just send the token
                // In a real implementation, we'd need to pass more context

                return RAC_TRUE;  // Continue generation
            };

            // Note: For a full implementation, we'd use rac_llm_generate_stream
            // For now, use non-streaming and send all at once
            rac_llm_result_t result = {};
            rac_result_t rc = rac_llm_generate(llmHandle_, prompt.c_str(), &options, &result);

            if (RAC_SUCCEEDED(rc) && result.text) {
                // Send the content
                rac_openai_stream_chunk_t chunk = {};
                chunk.id = cbData.requestId->c_str();
                chunk.object = "chat.completion.chunk";
                chunk.created = cbData.created;
                chunk.model = cbData.modelId->c_str();

                rac_openai_delta_t delta = {};
                delta.role = nullptr;
                delta.content = result.text;

                rac_openai_stream_choice_t choice = {};
                choice.index = 0;
                choice.delta = delta;
                choice.finish_reason = RAC_OPENAI_FINISH_NONE;

                chunk.choices = &choice;
                chunk.num_choices = 1;

                std::string sseData = json::formatSSE(json::serializeStreamChunk(chunk));
                sink.write(sseData.c_str(), sseData.size());

                // Send finish chunk
                delta.content = nullptr;
                choice.delta = delta;
                choice.finish_reason = RAC_OPENAI_FINISH_STOP;
                chunk.choices = &choice;

                sseData = json::formatSSE(json::serializeStreamChunk(chunk));
                sink.write(sseData.c_str(), sseData.size());

                *cbData.tokenCount += result.completion_tokens;
                totalTokensGenerated_ += result.completion_tokens;

                rac_llm_result_free(&result);
            }

            // Send done
            std::string doneData = json::formatSSEDone();
            sink.write(doneData.c_str(), doneData.size());

            sink.done();
            return true;
        }
    );

    res.status = 200;
}

std::string OpenAIHandler::buildPromptFromRequest(const nlohmann::json& requestJson) {
    std::ostringstream prompt;

    const auto& messages = requestJson["messages"];

    for (const auto& msg : messages) {
        std::string role = msg.value("role", "user");
        std::string content = msg.value("content", "");

        if (role == "system") {
            prompt << "System: " << content << "\n\n";
        } else if (role == "user") {
            prompt << "User: " << content << "\n\n";
        } else if (role == "assistant") {
            prompt << "Assistant: " << content << "\n\n";
        } else if (role == "tool") {
            std::string name = msg.value("name", "tool");
            prompt << "Tool Result (" << name << "): " << content << "\n\n";
        }
    }

    // Add tools if present
    if (requestJson.contains("tools") && requestJson["tools"].is_array()) {
        prompt << "You have access to the following tools:\n\n";

        for (const auto& tool : requestJson["tools"]) {
            if (tool.contains("function") && tool["function"].is_object()) {
                const auto& func = tool["function"];
                std::string name = func.value("name", "unknown");
                std::string desc = func.value("description", "");

                prompt << "- " << name;
                if (!desc.empty()) {
                    prompt << ": " << desc;
                }
                prompt << "\n";

                if (func.contains("parameters")) {
                    prompt << "  Parameters: " << func["parameters"].dump() << "\n";
                }
            }
        }

        prompt << "\nTo call a tool, respond with JSON: {\"tool_calls\": [{\"name\": \"...\", \"arguments\": {...}}]}\n\n";
    }

    prompt << "Assistant:";

    return prompt.str();
}

rac_llm_options_t OpenAIHandler::parseOptions(const nlohmann::json& requestJson) {
    rac_llm_options_t options = RAC_LLM_OPTIONS_DEFAULT;

    if (requestJson.contains("temperature") && requestJson["temperature"].is_number()) {
        options.temperature = requestJson["temperature"].get<float>();
    }

    if (requestJson.contains("top_p") && requestJson["top_p"].is_number()) {
        options.top_p = requestJson["top_p"].get<float>();
    }

    if (requestJson.contains("max_tokens") && requestJson["max_tokens"].is_number()) {
        options.max_tokens = requestJson["max_tokens"].get<int32_t>();
    }

    return options;
}

void OpenAIHandler::sendError(httplib::Response& res, int statusCode,
                               const std::string& message, const std::string& type) {
    auto errorJson = json::createErrorResponse(message, type, statusCode);
    res.set_content(errorJson.dump(), "application/json");
    res.status = statusCode;
}

} // namespace server
} // namespace rac
