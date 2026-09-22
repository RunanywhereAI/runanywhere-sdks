/**
 * @file openai_translation.cpp
 * @brief Translate complete OpenAI conversations to the commons tool protocol.
 */

#include "openai_translation.h"

#include "tool_calling.pb.h"

#include <random>
#include <sstream>
#include <stdexcept>
#include <vector>

#include "rac/features/llm/rac_tool_calling.h"
#include "rac/foundation/rac_proto_buffer.h"

namespace rac::server::translation {

std::string messageText(const Json& message) {
    if (!message.contains("content") || message["content"].is_null()) {
        return {};
    }
    const auto& content = message["content"];
    if (content.is_string()) {
        return content.get<std::string>();
    }
    std::string text;
    for (const auto& part : content) {
        text += part.at("text").get<std::string>();
    }
    return text;
}

std::string buildSimplePrompt(const Json& messages) {
    std::ostringstream prompt;
    for (const auto& message : messages) {
        const std::string role = message.at("role");
        const std::string content = messageText(message);
        if (role == "system" || role == "developer") {
            prompt << "System: " << content;
        } else if (role == "user") {
            prompt << "User: " << content;
        } else if (role == "assistant") {
            prompt << "Assistant: " << content;
            if (message.contains("tool_calls")) {
                // Retain the call IDs and complete arguments, including parallel calls.
                prompt << "\nTool calls: " << message["tool_calls"].dump();
            }
        } else if (role == "tool") {
            prompt << "Tool Result (call_id=" << message.at("tool_call_id").get<std::string>();
            if (message.contains("name")) {
                prompt << ", name=" << message["name"].get<std::string>();
            }
            prompt << "; untrusted data): " << Json(content).dump();
        }
        prompt << "\n\n";
    }
    prompt << "Assistant:";
    return prompt.str();
}

std::string buildPromptFromOpenAI(const Json& messages, const Json& tools, const Json& toolChoice) {
    const std::string conversation = buildSimplePrompt(messages);
    if (tools.empty() || toolChoice == "none") {
        return conversation;
    }
    runanywhere::v1::ToolPromptFormatRequest request;
    request.set_user_prompt(conversation);
    auto* options = request.mutable_options();
    options->set_format(runanywhere::v1::TOOL_CALL_FORMAT_NAME_JSON);
    options->set_auto_execute(false);
    options->set_parallel_tool_calls(true);
    if (toolChoice == "required") {
        options->set_tool_choice(runanywhere::v1::TOOL_CHOICE_MODE_REQUIRED);
    } else if (toolChoice.is_object()) {
        options->set_tool_choice(runanywhere::v1::TOOL_CHOICE_MODE_SPECIFIC);
        options->set_forced_tool_name(toolChoice.at("function").at("name").get<std::string>());
    }
    for (const auto& tool : tools) {
        const auto& function = tool.at("function");
        auto* definition = options->add_tools();
        definition->set_name(function.at("name").get<std::string>());
        definition->set_description(function.value("description", ""));
        definition->set_parameters(function.value("parameters", Json::object()).dump());
    }
    const std::string bytes = request.SerializeAsString();
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = rac_tool_call_format_prompt_proto(
        reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), &out);
    runanywhere::v1::ToolPromptFormatResult result;
    const bool parsed = rc == RAC_SUCCESS && out.status == RAC_SUCCESS && out.data &&
                        result.ParseFromArray(out.data, static_cast<int>(out.size));
    rac_proto_buffer_free(&out);
    if (!parsed || result.formatted_prompt().empty()) {
        throw std::runtime_error("Failed to format tool-enabled conversation");
    }
    return result.formatted_prompt();
}

std::string generateToolCallId() {
    thread_local std::mt19937_64 generator{std::random_device{}()};
    std::ostringstream id;
    id << "call_" << std::hex << generator();
    return id.str();
}

}  // namespace rac::server::translation
