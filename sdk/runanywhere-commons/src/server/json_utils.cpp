/**
 * @file json_utils.cpp
 * @brief JSON utilities implementation
 */

#include "json_utils.h"
#include <sstream>

namespace rac {
namespace server {
namespace json {

// =============================================================================
// PARSING
// =============================================================================

bool parseChatRequest(const Json& json, rac_openai_chat_request_t& request) {
    try {
        // Initialize with defaults
        request = RAC_OPENAI_CHAT_REQUEST_DEFAULT;

        // Model (required)
        if (json.contains("model") && json["model"].is_string()) {
            // Note: caller must manage the lifetime of this string
            // We'll use a static buffer or the caller handles it
        }

        // Temperature
        if (json.contains("temperature") && json["temperature"].is_number()) {
            request.temperature = json["temperature"].get<float>();
        }

        // Top-p
        if (json.contains("top_p") && json["top_p"].is_number()) {
            request.top_p = json["top_p"].get<float>();
        }

        // Max tokens
        if (json.contains("max_tokens") && json["max_tokens"].is_number()) {
            request.max_tokens = json["max_tokens"].get<int32_t>();
        }

        // Stream
        if (json.contains("stream") && json["stream"].is_boolean()) {
            request.stream = json["stream"].get<bool>() ? RAC_TRUE : RAC_FALSE;
        }

        // Presence penalty
        if (json.contains("presence_penalty") && json["presence_penalty"].is_number()) {
            request.presence_penalty = json["presence_penalty"].get<float>();
        }

        // Frequency penalty
        if (json.contains("frequency_penalty") && json["frequency_penalty"].is_number()) {
            request.frequency_penalty = json["frequency_penalty"].get<float>();
        }

        // Tool choice
        if (json.contains("tool_choice")) {
            // Handled separately
        }

        return true;
    } catch (const std::exception&) {
        return false;
    }
}

bool parseMessages(const Json& json, std::vector<rac_openai_message_t>& messages) {
    try {
        if (!json.is_array()) {
            return false;
        }

        messages.clear();
        messages.reserve(json.size());

        for (const auto& msgJson : json) {
            rac_openai_message_t msg = {};

            // Role
            if (msgJson.contains("role") && msgJson["role"].is_string()) {
                std::string role = msgJson["role"].get<std::string>();
                if (role == "system") {
                    msg.role = RAC_OPENAI_ROLE_SYSTEM;
                } else if (role == "user") {
                    msg.role = RAC_OPENAI_ROLE_USER;
                } else if (role == "assistant") {
                    msg.role = RAC_OPENAI_ROLE_ASSISTANT;
                } else if (role == "tool") {
                    msg.role = RAC_OPENAI_ROLE_TOOL;
                }
            }

            // Content is stored separately (caller manages)
            msg.content = nullptr;
            msg.tool_call_id = nullptr;
            msg.name = nullptr;

            messages.push_back(msg);
        }

        return true;
    } catch (const std::exception&) {
        return false;
    }
}

bool parseTools(const Json& json, std::vector<rac_openai_tool_t>& tools) {
    try {
        if (!json.is_array()) {
            return false;
        }

        tools.clear();
        tools.reserve(json.size());

        for (const auto& toolJson : json) {
            rac_openai_tool_t tool = {};
            tool.type = "function";

            if (toolJson.contains("function") && toolJson["function"].is_object()) {
                const auto& func = toolJson["function"];

                // Function fields are stored separately (caller manages)
                tool.function.name = nullptr;
                tool.function.description = nullptr;
                tool.function.parameters_json = nullptr;
                tool.function.strict = RAC_FALSE;

                if (func.contains("strict") && func["strict"].is_boolean()) {
                    tool.function.strict = func["strict"].get<bool>() ? RAC_TRUE : RAC_FALSE;
                }
            }

            tools.push_back(tool);
        }

        return true;
    } catch (const std::exception&) {
        return false;
    }
}

// =============================================================================
// SERIALIZATION
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

// =============================================================================
// PROMPT BUILDING
// =============================================================================

std::string buildPrompt(const rac_openai_message_t* messages,
                        size_t numMessages,
                        bool includeSystemPrompt) {
    std::ostringstream prompt;

    for (size_t i = 0; i < numMessages; ++i) {
        const auto& msg = messages[i];

        if (!msg.content) {
            continue;
        }

        switch (msg.role) {
            case RAC_OPENAI_ROLE_SYSTEM:
                if (includeSystemPrompt) {
                    prompt << "System: " << msg.content << "\n\n";
                }
                break;

            case RAC_OPENAI_ROLE_USER:
                prompt << "User: " << msg.content << "\n\n";
                break;

            case RAC_OPENAI_ROLE_ASSISTANT:
                prompt << "Assistant: " << msg.content << "\n\n";
                break;

            case RAC_OPENAI_ROLE_TOOL:
                prompt << "Tool Result";
                if (msg.name) {
                    prompt << " (" << msg.name << ")";
                }
                prompt << ": " << msg.content << "\n\n";
                break;
        }
    }

    // Add the assistant prefix to prompt continuation
    prompt << "Assistant:";

    return prompt.str();
}

std::string buildPromptWithTools(const rac_openai_message_t* messages,
                                  size_t numMessages,
                                  const rac_openai_tool_t* tools,
                                  size_t numTools) {
    std::ostringstream prompt;

    // Add tools description at the beginning
    if (tools && numTools > 0) {
        prompt << "You have access to the following tools:\n\n";

        for (size_t i = 0; i < numTools; ++i) {
            const auto& tool = tools[i];
            if (tool.function.name) {
                prompt << "- " << tool.function.name;
                if (tool.function.description) {
                    prompt << ": " << tool.function.description;
                }
                prompt << "\n";

                if (tool.function.parameters_json) {
                    prompt << "  Parameters: " << tool.function.parameters_json << "\n";
                }
            }
        }

        prompt << "\nTo call a tool, respond with JSON in this format:\n";
        prompt << "{\"tool_calls\": [{\"name\": \"tool_name\", \"arguments\": {}}]}\n\n";
    }

    // Add messages
    prompt << buildPrompt(messages, numMessages, true);

    return prompt.str();
}

} // namespace json
} // namespace server
} // namespace rac
