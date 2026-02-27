/**
 * @file openai_handler.cpp
 * @brief OpenAI API endpoint handlers implementation
 *
 * Uses Commons tool calling APIs via the translation layer.
 */

#include "openai_handler.h"
#include "json_utils.h"
#include "openai_translation.h"
#include "rac/backends/rac_llm_llamacpp.h"
#include "rac/core/rac_logger.h"
#include "rac/features/llm/rac_tool_calling.h"

#include <chrono>
#include <sstream>
#include <random>

namespace rac {
namespace server {

namespace {

// Generate a random ID for requests
std::string generateId(const std::string& prefix) {
    thread_local std::random_device rd;
    thread_local std::mt19937 gen(rd());
    thread_local std::uniform_int_distribution<uint64_t> dis;

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
    if (llmHandle_) {
        response["model_loaded"] = rac_llm_llamacpp_is_model_loaded(llmHandle_) != 0;
    } else {
        response["model_loaded"] = false;
    }

    res.set_content(response.dump(), "application/json");
    res.status = 200;
}

void OpenAIHandler::processNonStreaming(const httplib::Request& /*req*/,
                                         httplib::Response& res,
                                         const nlohmann::json& requestJson) {
    RAC_LOG_INFO("Server", "processNonStreaming: START");

    // Get messages and tools from request
    const auto& messages = requestJson["messages"];
    nlohmann::json tools = requestJson.value("tools", nlohmann::json::array());
    RAC_LOG_INFO("Server", "processNonStreaming: messages count=%zu, tools count=%zu",
                 messages.size(), tools.size());

    // Build prompt using translation layer (which uses Commons APIs)
    RAC_LOG_INFO("Server", "processNonStreaming: building prompt...");
    std::string prompt = translation::buildPromptFromOpenAI(messages, tools, nullptr);
    RAC_LOG_INFO("Server", "processNonStreaming: prompt built, length=%zu", prompt.length());

    // DEBUG: Log the messages JSON and built prompt
    RAC_LOG_DEBUG("Server", "=== REQUEST MESSAGES JSON ===");
    RAC_LOG_DEBUG("Server", "%s", messages.dump(2).c_str());
    RAC_LOG_DEBUG("Server", "=== BUILT PROMPT (first 2000 chars) ===");
    RAC_LOG_DEBUG("Server", "%s", prompt.substr(0, 2000).c_str());
    RAC_LOG_DEBUG("Server", "=== END PROMPT ===");

    // Parse LLM options
    rac_llm_options_t options = parseOptions(requestJson);
    RAC_LOG_INFO("Server", "processNonStreaming: options parsed, max_tokens=%d, temp=%.2f",
                 options.max_tokens, options.temperature);

    // Generate response using LlamaCPP backend directly
    RAC_LOG_INFO("Server", "processNonStreaming: calling rac_llm_llamacpp_generate with handle=%p", (void*)llmHandle_);
    rac_llm_result_t result = {};
    rac_result_t rc = rac_llm_llamacpp_generate(llmHandle_, prompt.c_str(), &options, &result);
    RAC_LOG_INFO("Server", "processNonStreaming: rac_llm_llamacpp_generate returned rc=%d", rc);

    if (RAC_FAILED(rc)) {
        rac_llm_result_free(&result);
        sendError(res, 500, "Generation failed", "server_error");
        return;
    }

    // Update token count
    totalTokensGenerated_ += result.completion_tokens;

    // Check if the response contains a tool call using Commons API
    rac_tool_call_t toolCall = {};
    bool hasToolCall = false;

    if (result.text && !tools.empty()) {
        rac_result_t parseResult = rac_tool_call_parse(result.text, &toolCall);
        hasToolCall = (parseResult == RAC_SUCCESS && toolCall.has_tool_call);
    }

    // Build response
    std::string requestId = generateId("chatcmpl-");

    rac_openai_chat_response_t response = {};
    response.id = const_cast<char*>(requestId.c_str());
    response.object = "chat.completion";
    response.created = currentTimestamp();
    response.model = modelId_.c_str();

    // Create message with potential tool calls
    rac_openai_assistant_message_t message = {};
    message.role = RAC_OPENAI_ROLE_ASSISTANT;

    // Tool call storage (for lifetime management)
    rac_openai_tool_call_t openaiToolCall = {};
    std::string toolCallId;
    std::string toolName;
    std::string toolArgs;

    if (hasToolCall) {
        // Convert Commons tool call to OpenAI format
        toolCallId = translation::generateToolCallId();
        toolName = toolCall.tool_name ? toolCall.tool_name : "";
        toolArgs = toolCall.arguments_json ? toolCall.arguments_json : "{}";

        openaiToolCall.id = toolCallId.c_str();
        openaiToolCall.type = "function";
        openaiToolCall.function_name = toolName.c_str();
        openaiToolCall.function_arguments = toolArgs.c_str();

        message.content = toolCall.clean_text; // Text without tool call tags
        message.tool_calls = &openaiToolCall;
        message.num_tool_calls = 1;
    } else {
        message.content = result.text;
        message.tool_calls = nullptr;
        message.num_tool_calls = 0;
    }

    rac_openai_choice_t choice = {};
    choice.index = 0;
    choice.message = message;
    choice.finish_reason = hasToolCall ? RAC_OPENAI_FINISH_TOOL_CALLS : RAC_OPENAI_FINISH_STOP;

    response.choices = &choice;
    response.num_choices = 1;

    response.usage.prompt_tokens = result.prompt_tokens;
    response.usage.completion_tokens = result.completion_tokens;
    response.usage.total_tokens = result.total_tokens;

    auto jsonResponse = json::serializeChatResponse(response);

    // Clean up
    rac_llm_result_free(&result);
    if (hasToolCall) {
        rac_tool_call_free(&toolCall);
    }

    res.set_content(jsonResponse.dump(), "application/json");
    res.status = 200;
}

void OpenAIHandler::processStreaming(const httplib::Request& /*req*/,
                                      httplib::Response& res,
                                      const nlohmann::json& requestJson) {
    // Get messages and tools from request
    const auto& messages = requestJson["messages"];
    nlohmann::json tools = requestJson.value("tools", nlohmann::json::array());

    // Build prompt using translation layer
    std::string prompt = translation::buildPromptFromOpenAI(messages, tools, nullptr);

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

    // Start streaming via content provider
    res.set_content_provider(
        "text/event-stream",
        [this, prompt, options, requestId, created](size_t /*offset*/, httplib::DataSink& sink) mutable {
            // First chunk: send role
            {
                rac_openai_stream_chunk_t chunk = {};
                chunk.id = requestId.c_str();
                chunk.object = "chat.completion.chunk";
                chunk.created = created;
                chunk.model = modelId_.c_str();

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
            }

            // Stream tokens incrementally via rac_llm_llamacpp_generate_stream
            struct StreamCtx {
                httplib::DataSink* sink;
                const std::string* requestId;
                const std::string* modelId;
                int64_t created;
                int32_t tokenCount;
            };

            StreamCtx ctx = { &sink, &requestId, &modelId_, created, 0 };

            auto streamCallback = [](const char* token, rac_bool_t is_final, void* user_data) -> rac_bool_t {
                auto* ctx = static_cast<StreamCtx*>(user_data);

                if (is_final) {
                    // Send finish chunk
                    rac_openai_stream_chunk_t chunk = {};
                    chunk.id = ctx->requestId->c_str();
                    chunk.object = "chat.completion.chunk";
                    chunk.created = ctx->created;
                    chunk.model = ctx->modelId->c_str();

                    rac_openai_delta_t delta = {};
                    delta.role = nullptr;
                    delta.content = nullptr;

                    rac_openai_stream_choice_t choice = {};
                    choice.index = 0;
                    choice.delta = delta;
                    choice.finish_reason = RAC_OPENAI_FINISH_STOP;

                    chunk.choices = &choice;
                    chunk.num_choices = 1;

                    std::string sseData = json::formatSSE(json::serializeStreamChunk(chunk));
                    ctx->sink->write(sseData.c_str(), sseData.size());
                } else if (token && token[0] != '\0') {
                    // Send content chunk with this token
                    rac_openai_stream_chunk_t chunk = {};
                    chunk.id = ctx->requestId->c_str();
                    chunk.object = "chat.completion.chunk";
                    chunk.created = ctx->created;
                    chunk.model = ctx->modelId->c_str();

                    rac_openai_delta_t delta = {};
                    delta.role = nullptr;
                    delta.content = token;

                    rac_openai_stream_choice_t choice = {};
                    choice.index = 0;
                    choice.delta = delta;
                    choice.finish_reason = RAC_OPENAI_FINISH_NONE;

                    chunk.choices = &choice;
                    chunk.num_choices = 1;

                    std::string sseData = json::formatSSE(json::serializeStreamChunk(chunk));
                    ctx->sink->write(sseData.c_str(), sseData.size());
                    ctx->tokenCount++;
                }

                return RAC_TRUE;  // Continue generating
            };

            rac_result_t rc = rac_llm_llamacpp_generate_stream(
                llmHandle_, prompt.c_str(), &options, streamCallback, &ctx);

            if (RAC_FAILED(rc)) {
                RAC_LOG_ERROR("Server", "Streaming generation failed: %d", rc);
            }

            totalTokensGenerated_ += ctx.tokenCount;

            // Send [DONE]
            std::string doneData = json::formatSSEDone();
            sink.write(doneData.c_str(), doneData.size());

            sink.done();
            return true;
        }
    );

    res.status = 200;
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
