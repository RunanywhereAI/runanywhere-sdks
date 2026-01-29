/**
 * @file json_utils.cpp
 * @brief JSON utilities for OpenAI API serialization
 *
 * This file handles OpenAI-specific JSON format serialization.
 * Prompt building is delegated to Commons (rac_tool_calling.h).
 */

#include "json_utils.h"
#include <sstream>

namespace rac {
namespace server {
namespace json {

// =============================================================================
// SERIALIZATION (C types -> JSON)
// =============================================================================

Json serializeChatResponse(const rac_openai_chat_response_t& response) {
    Json json;

    json["id"] = response.id ? response.id : "";
    json["object"] = "chat.completion";
    json["created"] = response.created;
    json["model"] = response.model ? response.model : "";

    // Choices
    Json choices = Json::array();
    for (size_t i = 0; i < response.num_choices; ++i) {
        const auto& choice = response.choices[i];
        Json choiceJson;

        choiceJson["index"] = choice.index;

        // Message
        Json message;
        message["role"] = "assistant";

        if (choice.message.content) {
            message["content"] = choice.message.content;
        } else {
            message["content"] = nullptr;
        }

        // Tool calls
        if (choice.message.num_tool_calls > 0 && choice.message.tool_calls) {
            Json toolCalls = Json::array();
            for (size_t j = 0; j < choice.message.num_tool_calls; ++j) {
                toolCalls.push_back(serializeToolCall(choice.message.tool_calls[j]));
            }
            message["tool_calls"] = toolCalls;
        }

        choiceJson["message"] = message;

        // Finish reason
        const char* finishStr = rac_openai_finish_reason_to_string(choice.finish_reason);
        if (finishStr) {
            choiceJson["finish_reason"] = finishStr;
        } else {
            choiceJson["finish_reason"] = nullptr;
        }

        choices.push_back(choiceJson);
    }
    json["choices"] = choices;

    // Usage
    json["usage"] = serializeUsage(response.usage);

    // System fingerprint (optional)
    if (response.system_fingerprint) {
        json["system_fingerprint"] = response.system_fingerprint;
    }

    return json;
}

Json serializeStreamChunk(const rac_openai_stream_chunk_t& chunk) {
    Json json;

    json["id"] = chunk.id ? chunk.id : "";
    json["object"] = "chat.completion.chunk";
    json["created"] = chunk.created;
    json["model"] = chunk.model ? chunk.model : "";

    // Choices
    Json choices = Json::array();
    for (size_t i = 0; i < chunk.num_choices; ++i) {
        const auto& choice = chunk.choices[i];
        Json choiceJson;

        choiceJson["index"] = choice.index;

        // Delta
        Json delta;
        if (choice.delta.role) {
            delta["role"] = choice.delta.role;
        }
        if (choice.delta.content) {
            delta["content"] = choice.delta.content;
        }
        if (choice.delta.num_tool_calls > 0 && choice.delta.tool_calls) {
            Json toolCalls = Json::array();
            for (size_t j = 0; j < choice.delta.num_tool_calls; ++j) {
                toolCalls.push_back(serializeToolCall(choice.delta.tool_calls[j]));
            }
            delta["tool_calls"] = toolCalls;
        }
        choiceJson["delta"] = delta;

        // Finish reason
        const char* finishStr = rac_openai_finish_reason_to_string(choice.finish_reason);
        if (finishStr) {
            choiceJson["finish_reason"] = finishStr;
        } else {
            choiceJson["finish_reason"] = nullptr;
        }

        choices.push_back(choiceJson);
    }
    json["choices"] = choices;

    return json;
}

Json serializeModelsResponse(const rac_openai_models_response_t& response) {
    Json json;

    json["object"] = "list";

    Json data = Json::array();
    for (size_t i = 0; i < response.num_data; ++i) {
        data.push_back(serializeModel(response.data[i]));
    }
    json["data"] = data;

    return json;
}

Json serializeModel(const rac_openai_model_t& model) {
    Json json;

    json["id"] = model.id ? model.id : "";
    json["object"] = "model";
    json["created"] = model.created;
    json["owned_by"] = model.owned_by ? model.owned_by : "runanywhere";

    return json;
}

Json serializeUsage(const rac_openai_usage_t& usage) {
    Json json;

    json["prompt_tokens"] = usage.prompt_tokens;
    json["completion_tokens"] = usage.completion_tokens;
    json["total_tokens"] = usage.total_tokens;

    return json;
}

Json serializeToolCall(const rac_openai_tool_call_t& toolCall) {
    Json json;

    json["id"] = toolCall.id ? toolCall.id : "";
    json["type"] = "function";

    Json function;
    function["name"] = toolCall.function_name ? toolCall.function_name : "";
    function["arguments"] = toolCall.function_arguments ? toolCall.function_arguments : "{}";
    json["function"] = function;

    return json;
}

Json createErrorResponse(const std::string& message, const std::string& type, int code) {
    Json json;

    Json error;
    error["message"] = message;
    error["type"] = type;
    error["code"] = code;

    json["error"] = error;

    return json;
}

// =============================================================================
// STREAMING HELPERS
// =============================================================================

std::string formatSSE(const Json& chunk) {
    std::ostringstream ss;
    ss << "data: " << chunk.dump() << "\n\n";
    return ss.str();
}

std::string formatSSEDone() {
    return "data: [DONE]\n\n";
}

} // namespace json
} // namespace server
} // namespace rac
