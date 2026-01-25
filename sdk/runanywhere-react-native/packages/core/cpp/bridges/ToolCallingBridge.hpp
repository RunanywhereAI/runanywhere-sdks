/**
 * @file ToolCallingBridge.hpp
 * @brief Tool Calling bridge for React Native
 *
 * Matches Swift's RunAnywhere+ToolCalling.swift pattern, providing:
 * - Tool call parsing from LLM output
 * - Tool definitions formatting for prompts
 *
 * Note: Implements parsing logic directly rather than depending on RACommons
 * rac_tool_calling.h, which allows building without rebuilding the xcframework.
 */

#pragma once

#include <string>

namespace runanywhere {
namespace bridges {

/**
 * @brief Tool calling result from parseToolCall
 */
struct ToolCallParseResult {
    bool hasToolCall = false;
    std::string toolName;
    std::string argumentsJson;
    std::string cleanText;
    int callId = 0;
};

/**
 * @brief Tool Calling bridge singleton
 *
 * Parses LLM output for tool calls and formats tools for prompts.
 */
class ToolCallingBridge {
public:
    static ToolCallingBridge& shared();

    /**
     * Format tool definitions into a system prompt
     * @param toolsJson JSON array of tool definitions
     * @return Formatted system prompt string with tool instructions
     */
    std::string formatToolsPrompt(const std::string& toolsJson);

    /**
     * Parse LLM output for tool calls
     * @param llmOutput Raw LLM output text
     * @return JSON string with hasToolCall, toolName, argumentsJson, cleanText
     */
    std::string parseToolCall(const std::string& llmOutput);

private:
    ToolCallingBridge() = default;
    ~ToolCallingBridge() = default;

    ToolCallingBridge(const ToolCallingBridge&) = delete;
    ToolCallingBridge& operator=(const ToolCallingBridge&) = delete;

    /**
     * Escape a string for JSON output
     */
    std::string escapeJsonString(const std::string& input);

    /**
     * Normalize JSON by adding quotes around unquoted keys
     * Handles: {tool: "name"} -> {"tool": "name"}
     */
    std::string normalizeJson(const std::string& json);

    /**
     * Extract a string value from JSON
     */
    bool extractJsonString(const std::string& json, const std::string& key, std::string& outValue);

    /**
     * Extract an object value from JSON
     */
    bool extractJsonObject(const std::string& json, const std::string& key, std::string& outValue);
};

} // namespace bridges
} // namespace runanywhere
