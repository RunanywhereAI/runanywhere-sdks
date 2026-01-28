/**
 * @file openai_translation.cpp
 * @brief Translation layer implementation
 */

#include "openai_translation.h"
#include <random>
#include <sstream>
#include <cstdlib>

namespace rac {
namespace server {
namespace translation {

// =============================================================================
// OpenAI REQUEST -> Commons Format
// =============================================================================

std::string openaiToolsToCommonsJson(const Json& openaiTools) {
    if (!openaiTools.is_array() || openaiTools.empty()) {
        return "[]";
    }

    Json commonsTools = Json::array();

    for (const auto& tool : openaiTools) {
        if (!tool.contains("function") || !tool["function"].is_object()) {
            continue;
        }

        const auto& func = tool["function"];
        Json commonsTool;

        // Name (required)
        if (func.contains("name") && func["name"].is_string()) {
            commonsTool["name"] = func["name"];
        } else {
            continue; // Skip invalid tool
        }

        // Description
        if (func.contains("description") && func["description"].is_string()) {
            commonsTool["description"] = func["description"];
        } else {
            commonsTool["description"] = "";
        }

        // Parameters - convert from OpenAI JSON Schema to Commons format
        Json commonsParams = Json::array();
        if (func.contains("parameters") && func["parameters"].is_object()) {
            const auto& params = func["parameters"];

            if (params.contains("properties") && params["properties"].is_object()) {
                // Get required fields
                std::vector<std::string> required;
                if (params.contains("required") && params["required"].is_array()) {
                    for (const auto& r : params["required"]) {
                        if (r.is_string()) {
                            required.push_back(r.get<std::string>());
                        }
                    }
                }

                // Convert each property
                for (auto& [propName, propValue] : params["properties"].items()) {
                    Json param;
                    param["name"] = propName;

                    // Type
                    if (propValue.contains("type") && propValue["type"].is_string()) {
                        param["type"] = propValue["type"];
                    } else {
                        param["type"] = "string";
                    }

                    // Description
                    if (propValue.contains("description") && propValue["description"].is_string()) {
                        param["description"] = propValue["description"];
                    } else {
                        param["description"] = "";
                    }

                    // Required
                    bool isRequired = std::find(required.begin(), required.end(), propName) != required.end();
                    param["required"] = isRequired;

                    // Enum values
                    if (propValue.contains("enum") && propValue["enum"].is_array()) {
                        param["enum"] = propValue["enum"];
                    }

                    commonsParams.push_back(param);
                }
            }
        }
        commonsTool["parameters"] = commonsParams;

        commonsTools.push_back(commonsTool);
    }

    return commonsTools.dump();
}

std::string buildPromptFromOpenAI(const Json& messages,
                                   const Json& tools,
                                   const rac_tool_calling_options_t* options) {
    // If no tools, build simple prompt
    if (!tools.is_array() || tools.empty()) {
        return buildSimplePrompt(messages);
    }

    // Convert OpenAI tools to Commons format
    std::string commonsToolsJson = openaiToolsToCommonsJson(tools);

    // Extract user message
    std::string userMessage = extractLastUserMessage(messages);

    // Use Commons API to build prompt
    char* prompt = nullptr;
    rac_result_t result = rac_tool_call_build_initial_prompt(
        userMessage.c_str(),
        commonsToolsJson.c_str(),
        options,
        &prompt
    );

    if (result != RAC_SUCCESS || !prompt) {
        // Fallback to simple prompt
        return buildSimplePrompt(messages);
    }

    std::string promptStr(prompt);
    free(prompt);

    return promptStr;
}

// =============================================================================
// Commons Format -> OpenAI RESPONSE
// =============================================================================

Json commonsToolCallToOpenAI(const rac_tool_call_t& toolCall) {
    Json toolCalls = Json::array();

    if (toolCall.has_tool_call && toolCall.tool_name) {
        Json tc;
        tc["id"] = generateToolCallId();
        tc["type"] = "function";

        Json function;
        function["name"] = toolCall.tool_name;
        function["arguments"] = toolCall.arguments_json ? toolCall.arguments_json : "{}";

        tc["function"] = function;
        toolCalls.push_back(tc);
    }

    return toolCalls;
}

std::string generateToolCallId() {
    static std::random_device rd;
    static std::mt19937 gen(rd());
    static std::uniform_int_distribution<uint64_t> dis;

    std::ostringstream ss;
    ss << "call_" << std::hex << dis(gen);
    return ss.str();
}

// =============================================================================
// Message Formatting
// =============================================================================

std::string extractLastUserMessage(const Json& messages) {
    if (!messages.is_array()) {
        return "";
    }

    // Find last user message
    for (auto it = messages.rbegin(); it != messages.rend(); ++it) {
        if (it->contains("role") && (*it)["role"] == "user") {
            if (it->contains("content") && (*it)["content"].is_string()) {
                return (*it)["content"].get<std::string>();
            }
        }
    }

    return "";
}

std::string buildSimplePrompt(const Json& messages) {
    if (!messages.is_array()) {
        return "";
    }

    std::ostringstream prompt;

    for (const auto& msg : messages) {
        std::string role = msg.value("role", "user");
        std::string content = msg.value("content", "");

        if (content.empty()) {
            continue;
        }

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

    prompt << "Assistant:";

    return prompt.str();
}

} // namespace translation
} // namespace server
} // namespace rac
