/**
 * @file ToolCallingBridge.cpp
 * @brief Tool Calling bridge implementation - THIN WRAPPER
 *
 * *** ALL LOGIC IS IN runanywhere-commons (rac_tool_calling.h) ***
 *
 * This bridge just wraps the C API functions from commons.
 * NO LOCAL PARSING LOGIC - everything calls through to commons.
 */

#include "ToolCallingBridge.hpp"
#include <rac_tool_calling.h>
#include <nlohmann/json.hpp>
#include <cstring>

using json = nlohmann::json;

namespace runanywhere {
namespace bridges {

ToolCallingBridge& ToolCallingBridge::shared() {
    static ToolCallingBridge instance;
    return instance;
}

std::string ToolCallingBridge::parseToolCall(const std::string& llmOutput) {
    rac_tool_call_t result;
    rac_result_t rc = rac_tool_call_parse(llmOutput.c_str(), &result);
    
    // Build JSON response using nlohmann/json
    json response;
    response["hasToolCall"] = result.has_tool_call == RAC_TRUE;
    response["cleanText"] = result.clean_text ? result.clean_text : llmOutput;
    
    if (result.has_tool_call == RAC_TRUE) {
        response["toolName"] = result.tool_name ? result.tool_name : "";
        
        if (result.arguments_json) {
            try {
                response["argumentsJson"] = json::parse(result.arguments_json);
            } catch (...) {
                response["argumentsJson"] = json::object();
            }
        } else {
            response["argumentsJson"] = json::object();
        }
        response["callId"] = result.call_id;
    }
    
    rac_tool_call_free(&result);
    return response.dump();
}

std::string ToolCallingBridge::formatToolsPrompt(const std::string& toolsJson) {
    if (toolsJson.empty() || toolsJson == "[]") {
        return "";
    }
    
    char* prompt = nullptr;
    rac_result_t rc = rac_tool_call_format_prompt_json(toolsJson.c_str(), &prompt);
    
    if (rc != RAC_SUCCESS || !prompt) {
        return "";
    }
    
    std::string result(prompt);
    rac_free(prompt);
    return result;
}

std::string ToolCallingBridge::buildInitialPrompt(
    const std::string& userPrompt,
    const std::string& toolsJson,
    const std::string& optionsJson
) {
    // Use default options for now
    rac_tool_calling_options_t options = {5, RAC_TRUE, 0.7f, 1024, nullptr, RAC_FALSE, RAC_FALSE};
    
    char* prompt = nullptr;
    rac_result_t rc = rac_tool_call_build_initial_prompt(
        userPrompt.c_str(), 
        toolsJson.c_str(), 
        &options, 
        &prompt
    );
    
    if (rc != RAC_SUCCESS || !prompt) {
        return userPrompt;
    }
    
    std::string result(prompt);
    rac_free(prompt);
    return result;
}

std::string ToolCallingBridge::buildFollowupPrompt(
    const std::string& originalPrompt,
    const std::string& toolsPrompt,
    const std::string& toolName,
    const std::string& resultJson,
    bool keepToolsAvailable
) {
    char* prompt = nullptr;
    rac_result_t rc = rac_tool_call_build_followup_prompt(
        originalPrompt.c_str(),
        toolsPrompt.empty() ? nullptr : toolsPrompt.c_str(),
        toolName.c_str(),
        resultJson.c_str(),
        keepToolsAvailable ? RAC_TRUE : RAC_FALSE,
        &prompt
    );
    
    if (rc != RAC_SUCCESS || !prompt) {
        return "";
    }
    
    std::string result(prompt);
    rac_free(prompt);
    return result;
}

std::string ToolCallingBridge::normalizeJson(const std::string& jsonStr) {
    char* normalized = nullptr;
    rac_result_t rc = rac_tool_call_normalize_json(jsonStr.c_str(), &normalized);
    
    if (rc != RAC_SUCCESS || !normalized) {
        return jsonStr;
    }
    
    std::string result(normalized);
    rac_free(normalized);
    return result;
}

} // namespace bridges
} // namespace runanywhere
