/**
 * @file ToolCallingBridge.cpp
 * @brief Tool Calling bridge implementation
 *
 * Implements tool call parsing and prompt formatting directly.
 * This avoids dependency on rac_tool_calling.h which may not be in the
 * pre-built xcframework.
 */

#include "ToolCallingBridge.hpp"
#include <sstream>
#include <cstring>

namespace runanywhere {
namespace bridges {

// Tool call tag definitions (matching RACommons tool_calling.cpp)
static const char* TOOL_CALL_START_TAG = "<tool_call>";
static const char* TOOL_CALL_END_TAG = "</tool_call>";

ToolCallingBridge& ToolCallingBridge::shared() {
    static ToolCallingBridge instance;
    return instance;
}

std::string ToolCallingBridge::escapeJsonString(const std::string& input) {
    std::string escaped;
    escaped.reserve(input.size() + 16);

    for (char c : input) {
        switch (c) {
            case '"':  escaped += "\\\""; break;
            case '\\': escaped += "\\\\"; break;
            case '\n': escaped += "\\n"; break;
            case '\r': escaped += "\\r"; break;
            case '\t': escaped += "\\t"; break;
            default:   escaped += c; break;
        }
    }

    return escaped;
}

/**
 * Normalize JSON by adding quotes around unquoted keys
 * Handles: {tool: "name"} -> {"tool": "name"}
 */
std::string ToolCallingBridge::normalizeJson(const std::string& json) {
    std::string result;
    result.reserve(json.size() + 32);

    bool inString = false;
    for (size_t i = 0; i < json.size(); i++) {
        char c = json[i];

        // Track if we're inside a string
        if (c == '"' && (i == 0 || json[i-1] != '\\')) {
            inString = !inString;
            result += c;
            continue;
        }

        if (inString) {
            result += c;
            continue;
        }

        // Look for unquoted keys: { key: or , key:
        if ((c == '{' || c == ',') && i + 1 < json.size()) {
            result += c;
            // Skip whitespace
            size_t j = i + 1;
            while (j < json.size() && (json[j] == ' ' || json[j] == '\t' || json[j] == '\n')) {
                result += json[j];
                j++;
            }
            // Check if next is an unquoted identifier followed by colon
            if (j < json.size() && json[j] != '"' && json[j] != '{' && json[j] != '[') {
                size_t keyStart = j;
                while (j < json.size() && json[j] != ':' && json[j] != ' ' && json[j] != '\t') {
                    j++;
                }
                if (j < json.size()) {
                    // Skip whitespace to find colon
                    size_t keyEnd = j;
                    while (j < json.size() && (json[j] == ' ' || json[j] == '\t')) j++;
                    if (j < json.size() && json[j] == ':') {
                        // This is an unquoted key - add quotes
                        result += '"';
                        result += json.substr(keyStart, keyEnd - keyStart);
                        result += '"';
                        i = keyEnd - 1; // -1 because loop will increment
                        continue;
                    }
                }
            }
            i = j - 1; // -1 because loop will increment
            continue;
        }

        result += c;
    }

    return result;
}

bool ToolCallingBridge::extractJsonString(const std::string& json, const std::string& key, std::string& outValue) {
    // Normalize JSON first to handle unquoted keys
    std::string normalizedJson = normalizeJson(json);

    // Build search pattern: "key"
    std::string pattern = "\"" + key + "\"";

    size_t keyPos = normalizedJson.find(pattern);
    if (keyPos == std::string::npos) {
        return false;
    }

    // Find the colon after the key
    size_t colonPos = normalizedJson.find(':', keyPos + pattern.length());
    if (colonPos == std::string::npos) {
        return false;
    }

    // Skip whitespace after colon
    size_t valueStart = colonPos + 1;
    while (valueStart < normalizedJson.size() && (normalizedJson[valueStart] == ' ' || normalizedJson[valueStart] == '\t' || normalizedJson[valueStart] == '\n')) {
        valueStart++;
    }

    // Check if value is a string (starts with quote)
    if (valueStart >= normalizedJson.size() || normalizedJson[valueStart] != '"') {
        return false;
    }
    valueStart++; // Skip opening quote

    // Find closing quote (handle escaped quotes)
    size_t valueEnd = valueStart;
    while (valueEnd < normalizedJson.size()) {
        if (normalizedJson[valueEnd] == '"' && (valueEnd == 0 || normalizedJson[valueEnd - 1] != '\\')) {
            break;
        }
        valueEnd++;
    }

    if (valueEnd >= normalizedJson.size()) {
        return false;
    }

    outValue = normalizedJson.substr(valueStart, valueEnd - valueStart);
    return true;
}

bool ToolCallingBridge::extractJsonObject(const std::string& json, const std::string& key, std::string& outValue) {
    // Build search pattern: "key"
    std::string pattern = "\"" + key + "\"";

    size_t keyPos = json.find(pattern);
    if (keyPos == std::string::npos) {
        return false;
    }

    // Find the colon after the key
    size_t colonPos = json.find(':', keyPos + pattern.length());
    if (colonPos == std::string::npos) {
        return false;
    }

    // Skip whitespace after colon
    size_t valueStart = colonPos + 1;
    while (valueStart < json.size() && (json[valueStart] == ' ' || json[valueStart] == '\t' || json[valueStart] == '\n')) {
        valueStart++;
    }

    // Check if value is an object (starts with brace)
    if (valueStart >= json.size() || json[valueStart] != '{') {
        return false;
    }

    // Find matching closing brace
    int braceCount = 1;
    size_t pos = valueStart + 1;
    while (pos < json.size() && braceCount > 0) {
        if (json[pos] == '{') braceCount++;
        else if (json[pos] == '}') braceCount--;
        pos++;
    }

    if (braceCount != 0) {
        return false; // Unmatched braces
    }

    outValue = json.substr(valueStart, pos - valueStart);
    return true;
}

std::string ToolCallingBridge::formatToolsPrompt(const std::string& toolsJson) {
    if (toolsJson.empty() || toolsJson == "[]") {
        return "";
    }

    // Build a comprehensive system prompt for tool calling
    // This prompt is designed to work with models that support tool calling (3B+ recommended)
    std::ostringstream ss;

    ss << "# Available Tools\n\n";
    ss << "You have access to the following tools. ONLY use them when the user specifically asks for information that requires them:\n\n";
    ss << toolsJson << "\n\n";

    ss << "# Tool Usage Instructions\n\n";
    ss << "IMPORTANT RULES:\n";
    ss << "- For normal conversation (greetings, questions, chat), respond naturally WITHOUT using any tools.\n";
    ss << "- Only use a tool if the user explicitly asks for something the tool provides.\n";
    ss << "- Do NOT use tools for general questions or conversation.\n\n";

    ss << "When you DO need to use a tool, respond with:\n";
    ss << "<tool_call>{\"tool\": \"tool_name\", \"arguments\": {\"param1\": \"value1\"}}</tool_call>\n\n";

    ss << "If the user just says \"hello\" or asks a general question, respond normally without any tool calls.";

    return ss.str();
}

std::string ToolCallingBridge::parseToolCall(const std::string& llmOutput) {
    // Find tool call tags
    size_t tagStart = llmOutput.find(TOOL_CALL_START_TAG);

    if (tagStart == std::string::npos) {
        // No tool call found - return clean text with hasToolCall = false
        std::ostringstream ss;
        ss << "{";
        ss << "\"hasToolCall\":false,";
        ss << "\"cleanText\":\"" << escapeJsonString(llmOutput) << "\"";
        ss << "}";
        return ss.str();
    }

    // Find end tag
    size_t jsonStart = tagStart + strlen(TOOL_CALL_START_TAG);
    size_t tagEnd = llmOutput.find(TOOL_CALL_END_TAG, jsonStart);
    bool hasClosingTag = (tagEnd != std::string::npos);

    if (!hasClosingTag) {
        // No closing tag - find JSON by matching braces
        // This handles models that output: <tool_call>{"tool": "name", ...}
        // without the closing </tool_call>
        std::string jsonPart = llmOutput.substr(jsonStart);
        int braceCount = 0;
        size_t jsonEndIndex = std::string::npos;

        for (size_t i = 0; i < jsonPart.size(); i++) {
            if (jsonPart[i] == '{') braceCount++;
            else if (jsonPart[i] == '}') {
                braceCount--;
                if (braceCount == 0) {
                    jsonEndIndex = i + 1;
                    break;
                }
            }
        }

        if (jsonEndIndex == std::string::npos) {
            // Can't find valid JSON object
            std::ostringstream ss;
            ss << "{";
            ss << "\"hasToolCall\":false,";
            ss << "\"cleanText\":\"" << escapeJsonString(llmOutput) << "\"";
            ss << "}";
            return ss.str();
        }
        tagEnd = jsonStart + jsonEndIndex;
    }

    // Extract JSON between tags
    std::string toolJson = llmOutput.substr(jsonStart, tagEnd - jsonStart);

    // Parse tool name from JSON
    // Looking for: {"tool": "tool_name", "arguments": {...}}
    std::string toolName;
    if (!extractJsonString(toolJson, "tool", toolName)) {
        // Try alternative key "name"
        if (!extractJsonString(toolJson, "name", toolName)) {
            // Could not parse tool name
            std::ostringstream ss;
            ss << "{";
            ss << "\"hasToolCall\":false,";
            ss << "\"cleanText\":\"" << escapeJsonString(llmOutput) << "\"";
            ss << "}";
            return ss.str();
        }
    }

    // Parse arguments from JSON
    std::string arguments;
    if (!extractJsonObject(toolJson, "arguments", arguments)) {
        // Try alternative key "params"
        if (!extractJsonObject(toolJson, "params", arguments)) {
            // No arguments - use empty object
            arguments = "{}";
        }
    }

    // Build the clean text (everything except the tool call tags)
    std::string cleanText;
    cleanText = llmOutput.substr(0, tagStart);
    if (hasClosingTag) {
        cleanText += llmOutput.substr(tagEnd + strlen(TOOL_CALL_END_TAG));
    } else {
        // No closing tag - just take everything after the JSON
        cleanText += llmOutput.substr(tagEnd);
    }

    // Trim whitespace from clean text
    size_t start = cleanText.find_first_not_of(" \t\n\r");
    size_t end = cleanText.find_last_not_of(" \t\n\r");
    if (start != std::string::npos && end != std::string::npos) {
        cleanText = cleanText.substr(start, end - start + 1);
    } else {
        cleanText = "";
    }

    // Build JSON response
    std::ostringstream ss;
    ss << "{";
    ss << "\"hasToolCall\":true,";
    ss << "\"cleanText\":\"" << escapeJsonString(cleanText) << "\",";
    ss << "\"toolName\":\"" << escapeJsonString(toolName) << "\",";
    ss << "\"argumentsJson\":" << arguments << ",";
    ss << "\"callId\":0";
    ss << "}";

    return ss.str();
}

} // namespace bridges
} // namespace runanywhere
