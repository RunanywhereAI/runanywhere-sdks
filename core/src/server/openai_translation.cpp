/**
 * @file openai_translation.cpp
 * @brief Translate complete OpenAI conversations to the commons tool protocol.
 */

#include "openai_translation.h"

#include "llm_service.pb.h"
#include "tool_calling.pb.h"

#include <random>
#include <sstream>
#include <stdexcept>
#include <vector>

#include "rac/features/llm/rac_tool_calling.h"
#include "rac/foundation/rac_proto_buffer.h"

namespace rac::server::translation {
namespace {

runanywhere::v1::MessageRole messageRole(const std::string& role) {
    if (role == "user")
        return runanywhere::v1::MESSAGE_ROLE_USER;
    if (role == "assistant")
        return runanywhere::v1::MESSAGE_ROLE_ASSISTANT;
    if (role == "tool")
        return runanywhere::v1::MESSAGE_ROLE_TOOL;
    if (role == "developer")
        return runanywhere::v1::MESSAGE_ROLE_DEVELOPER;
    return runanywhere::v1::MESSAGE_ROLE_SYSTEM;
}

void addTools(const Json& request, runanywhere::v1::ToolCallingOptions* options) {
    options->set_auto_execute(false);
    options->set_format(runanywhere::v1::TOOL_CALL_FORMAT_NAME_JSON);
    options->set_parallel_tool_calls(request.value("parallel_tool_calls", true));
    options->set_require_json_arguments(true);
    for (const auto& tool : request.value("tools", Json::array())) {
        const auto& function = tool.at("function");
        auto* definition = options->add_tools();
        definition->set_name(function.at("name").get<std::string>());
        definition->set_description(function.value("description", ""));
        definition->set_parameters(function.value("parameters", Json::object()).dump());
    }
    const auto choice = request.value("tool_choice", Json("auto"));
    if (choice == "none") {
        options->set_tool_choice(runanywhere::v1::TOOL_CHOICE_MODE_NONE);
    } else if (choice == "required") {
        options->set_tool_choice(runanywhere::v1::TOOL_CHOICE_MODE_REQUIRED);
    } else if (choice.is_object()) {
        options->set_tool_choice(runanywhere::v1::TOOL_CHOICE_MODE_SPECIFIC);
        options->set_forced_tool_name(choice.at("function").at("name").get<std::string>());
    } else {
        options->set_tool_choice(runanywhere::v1::TOOL_CHOICE_MODE_AUTO);
    }
}

}  // namespace

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

runanywhere::v1::LLMGenerateRequest buildGenerateRequest(const Json& request,
                                                         const std::string& modelId) {
    runanywhere::v1::LLMGenerateRequest result;
    result.set_model_id(modelId);
    auto* options = result.mutable_options();
    options->set_max_output_tokens(4096);
    std::vector<std::string> systemParts;
    for (const auto& message : request.at("messages")) {
        const std::string role = message.at("role");
        const std::string content = messageText(message);
        if (role == "system") {
            systemParts.push_back(content);
            continue;
        }
        auto* translated = result.add_messages();
        translated->set_role(messageRole(role));
        translated->set_content(content);
        if (message.contains("name"))
            translated->set_name(message.at("name").get<std::string>());
        if (message.contains("tool_call_id"))
            translated->set_tool_call_id(message.at("tool_call_id").get<std::string>());
        for (const auto& call : message.value("tool_calls", Json::array())) {
            auto* translatedCall = translated->add_tool_calls();
            translatedCall->set_id(call.at("id").get<std::string>());
            translatedCall->set_name(call.at("function").at("name").get<std::string>());
            translatedCall->set_arguments_json(
                call.at("function").at("arguments").get<std::string>());
        }
        if (role == "tool") {
            auto* toolResult = translated->mutable_tool_result();
            toolResult->set_tool_call_id(message.at("tool_call_id").get<std::string>());
            toolResult->set_name(message.value("name", ""));
            toolResult->set_result_json(Json(content).dump());
        }
    }
    if (!systemParts.empty()) {
        std::ostringstream systemPrompt;
        for (size_t i = 0; i < systemParts.size(); ++i) {
            if (i)
                systemPrompt << "\n\n";
            systemPrompt << systemParts[i];
        }
        options->set_system_prompt(systemPrompt.str());
    }
    for (const char* key : {"max_tokens", "max_completion_tokens"}) {
        if (request.contains(key) && !request[key].is_null())
            options->set_max_output_tokens(request[key].get<int32_t>());
    }
    if (request.contains("temperature") && !request["temperature"].is_null())
        options->set_temperature(request["temperature"].get<float>());
    if (request.contains("top_p") && !request["top_p"].is_null())
        options->set_top_p(request["top_p"].get<float>());
    if (request.contains("frequency_penalty") && !request["frequency_penalty"].is_null())
        options->set_frequency_penalty(request["frequency_penalty"].get<float>());
    if (request.contains("presence_penalty") && !request["presence_penalty"].is_null())
        options->set_presence_penalty(request["presence_penalty"].get<float>());
    if (request.contains("seed") && !request["seed"].is_null())
        options->set_seed(request["seed"].get<int64_t>());
    if (request.contains("stop") && !request["stop"].is_null()) {
        if (request["stop"].is_string()) {
            options->add_stop_sequences(request["stop"].get<std::string>());
        } else {
            for (const auto& stop : request["stop"])
                options->add_stop_sequences(stop.get<std::string>());
        }
    }
    if (request.contains("tools"))
        addTools(request, options->mutable_tool_calling());
    return result;
}

std::string generateToolCallId() {
    thread_local std::mt19937_64 generator{std::random_device{}()};
    std::ostringstream id;
    id << "call_" << std::hex << generator();
    return id.str();
}

}  // namespace rac::server::translation
