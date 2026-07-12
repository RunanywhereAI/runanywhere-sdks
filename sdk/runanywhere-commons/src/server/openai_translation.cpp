/**
 * @file openai_translation.cpp
 * @brief Translation layer implementation
 */

#include "openai_translation.h"

#include "tool_calling.pb.h"

#include <random>
#include <sstream>
#include <unordered_set>
#include <vector>

#include "rac/features/llm/rac_tool_calling.h"
#include "rac/foundation/rac_proto_buffer.h"

namespace rac {
namespace server {
namespace translation {

namespace {

runanywhere::v1::ToolParameterType parameter_type(const Json& schema) {
    const std::string type = schema.value("type", "string");
    if (type == "number" || type == "integer") {
        return runanywhere::v1::TOOL_PARAMETER_TYPE_NUMBER;
    }
    if (type == "boolean") {
        return runanywhere::v1::TOOL_PARAMETER_TYPE_BOOLEAN;
    }
    if (type == "object") {
        return runanywhere::v1::TOOL_PARAMETER_TYPE_OBJECT;
    }
    if (type == "array") {
        return runanywhere::v1::TOOL_PARAMETER_TYPE_ARRAY;
    }
    return runanywhere::v1::TOOL_PARAMETER_TYPE_STRING;
}

void append_openai_tools(const Json& openai_tools, runanywhere::v1::ToolCallingOptions* options) {
    if (!options || !openai_tools.is_array()) {
        return;
    }
    for (const auto& tool : openai_tools) {
        if (!tool.contains("function") || !tool["function"].is_object()) {
            continue;
        }
        const auto& function = tool["function"];
        if (!function.contains("name") || !function["name"].is_string()) {
            continue;
        }

        auto* definition = options->add_tools();
        definition->set_name(function["name"].get<std::string>());
        definition->set_description(function.value("description", ""));

        if (!function.contains("parameters") || !function["parameters"].is_object()) {
            continue;
        }
        const auto& schema = function["parameters"];
        definition->set_json_schema(schema.dump());

        std::unordered_set<std::string> required;
        if (schema.contains("required") && schema["required"].is_array()) {
            for (const auto& name : schema["required"]) {
                if (name.is_string()) {
                    required.insert(name.get<std::string>());
                }
            }
        }
        if (!schema.contains("properties") || !schema["properties"].is_object()) {
            continue;
        }
        for (const auto& [name, property] : schema["properties"].items()) {
            if (!property.is_object()) {
                continue;
            }
            auto* parameter = definition->add_parameters();
            parameter->set_name(name);
            parameter->set_type(parameter_type(property));
            parameter->set_description(property.value("description", ""));
            parameter->set_required(required.contains(name));
            parameter->set_json_schema(property.dump());
            if (property.contains("enum") && property["enum"].is_array()) {
                for (const auto& value : property["enum"]) {
                    if (value.is_string()) {
                        parameter->add_enum_values(value.get<std::string>());
                    }
                }
            }
        }
    }
}

}  // namespace

// =============================================================================
// OpenAI REQUEST -> Commons Format
// =============================================================================

std::string buildPromptFromOpenAI(const Json& messages, const Json& tools) {
    // If no tools, build simple prompt
    if (!tools.is_array() || tools.empty()) {
        return buildSimplePrompt(messages);
    }

    runanywhere::v1::ToolPromptFormatRequest request;
    request.set_user_prompt(extractLastUserMessage(messages));
    auto* options = request.mutable_options();
    options->set_format(runanywhere::v1::TOOL_CALL_FORMAT_NAME_JSON);
    options->set_auto_execute(true);
    append_openai_tools(tools, options);

    std::vector<uint8_t> request_bytes(request.ByteSizeLong());
    if (!request.SerializeToArray(request_bytes.data(), static_cast<int>(request_bytes.size()))) {
        return buildSimplePrompt(messages);
    }

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc =
        rac_tool_call_format_prompt_proto(request_bytes.data(), request_bytes.size(), &out);
    runanywhere::v1::ToolPromptFormatResult result;
    const bool parsed = rc == RAC_SUCCESS && out.status == RAC_SUCCESS && out.data &&
                        result.ParseFromArray(out.data, static_cast<int>(out.size));
    rac_proto_buffer_free(&out);
    if (!parsed || result.formatted_prompt().empty()) {
        return buildSimplePrompt(messages);
    }
    return result.formatted_prompt();
}

std::string generateToolCallId() {
    thread_local std::random_device rd;
    thread_local std::mt19937 gen(rd());
    thread_local std::uniform_int_distribution<uint64_t> dis;

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

}  // namespace translation
}  // namespace server
}  // namespace rac
