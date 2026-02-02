/**
 * @file ToolCallingBridge.hpp
 * @brief Tool Calling bridge for React Native - THIN WRAPPER
 *
 * *** SINGLE SOURCE OF TRUTH FOR TOOL CALLING LOGIC IS IN COMMONS C++ ***
 *
 * All parsing logic is in runanywhere-commons (rac_tool_calling.h).
 * This bridge just wraps the C API for JSI access.
 *
 * ARCHITECTURE:
 * - Commons C++: ALL parsing, prompt formatting, JSON normalization
 * - This bridge: Thin wrapper that calls rac_tool_call_* functions
 * - TypeScript: Tool registry, execution (needs JS APIs)
 */

#pragma once

#include <string>

namespace runanywhere {
namespace bridges {

/**
 * Tool Calling bridge - thin wrapper around commons API
 *
 * *** NO LOCAL PARSING LOGIC - ALL CALLS GO TO COMMONS ***
 */
class ToolCallingBridge {
public:
    static ToolCallingBridge& shared();

    /**
     * Format tool definitions into a system prompt.
     * Calls rac_tool_call_format_prompt_json_with_format_name() from commons.
     *
     * @param toolsJson JSON array of tool definitions
     * @param format Format name ("default" or "lfm2")
     * @return Formatted system prompt string
     */
    std::string formatToolsPrompt(const std::string& toolsJson, const std::string& format = "default");

    /**
     * Parse LLM output for tool calls.
     * Calls rac_tool_call_parse() from commons.
     *
     * @param llmOutput Raw LLM output text
     * @return JSON string with hasToolCall, toolName, argumentsJson, cleanText
     */
    std::string parseToolCall(const std::string& llmOutput);

    /**
     * Build initial prompt with tools and user query.
     * Calls rac_tool_call_build_initial_prompt() from commons.
     *
     * @param userPrompt User's question/request
     * @param toolsJson JSON array of tool definitions
     * @param optionsJson Options as JSON (nullable)
     * @return Complete formatted prompt
     */
    std::string buildInitialPrompt(const std::string& userPrompt,
                                   const std::string& toolsJson,
                                   const std::string& optionsJson);

    /**
     * Build follow-up prompt after tool execution.
     * Calls rac_tool_call_build_followup_prompt() from commons.
     *
     * @param originalPrompt Original user prompt
     * @param toolsPrompt Formatted tools prompt (can be empty)
     * @param toolName Name of executed tool
     * @param resultJson Tool result as JSON
     * @param keepToolsAvailable Whether to keep tools in follow-up
     * @return Follow-up prompt string
     */
    std::string buildFollowupPrompt(const std::string& originalPrompt,
                                    const std::string& toolsPrompt,
                                    const std::string& toolName,
                                    const std::string& resultJson,
                                    bool keepToolsAvailable);

    /**
     * Normalize JSON by adding quotes around unquoted keys.
     * Calls rac_tool_call_normalize_json() from commons.
     *
     * @param jsonStr Raw JSON possibly with unquoted keys
     * @return Normalized JSON string
     */
    std::string normalizeJson(const std::string& jsonStr);

private:
    ToolCallingBridge() = default;
    ~ToolCallingBridge() = default;
    ToolCallingBridge(const ToolCallingBridge&) = delete;
    ToolCallingBridge& operator=(const ToolCallingBridge&) = delete;
};

} // namespace bridges
} // namespace runanywhere
