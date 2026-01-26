/**
 * @file ToolCallingBridge.hpp
 * @brief Tool Calling bridge for React Native
 *
 * Matches Swift's RunAnywhere+ToolCalling.swift pattern, providing:
 * - Tool call parsing from LLM output (SINGLE SOURCE OF TRUTH for parsing)
 * - Tool definitions formatting for prompts
 *
 * ARCHITECTURE:
 * This bridge handles ONLY the parsing of <tool_call> tags from LLM output.
 * Tool registration, execution, and prompt formatting are handled in TypeScript
 * (RunAnywhere+ToolCalling.ts) because executors need JavaScript APIs.
 *
 * JSON PARSING:
 * Uses nlohmann/json (https://github.com/nlohmann/json) for robust JSON parsing.
 * This handles:
 * - Properly escaped strings and special characters
 * - Nested objects and arrays
 * - Edge cases that simple string parsing would miss
 *
 * The normalizeJson() helper handles LLM quirks like unquoted keys:
 *   {tool: "name"} -> {"tool": "name"}
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
 * Uses nlohmann/json for robust JSON parsing.
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
     * Handles common LLM output patterns: {tool: "name"} -> {"tool": "name"}
     */
    std::string normalizeJson(const std::string& json);
};

} // namespace bridges
} // namespace runanywhere
