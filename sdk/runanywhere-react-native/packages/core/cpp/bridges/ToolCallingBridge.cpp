/**
 * @file ToolCallingBridge.cpp
 * @brief Tool Calling bridge implementation
 *
 * Implements tool call parsing using nlohmann/json for robust JSON handling.
 * This avoids dependency on rac_tool_calling.h which may not be in the
 * pre-built xcframework.
 */

#include "ToolCallingBridge.hpp"
#include <nlohmann/json.hpp>
#include <sstream>
#include <cstring>
#include <cctype>

using json = nlohmann::json;

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
    // Use nlohmann/json for proper escaping
    json j = input;
    std::string escaped = j.dump();
    // Remove surrounding quotes added by dump()
    if (escaped.size() >= 2 && escaped.front() == '"' && escaped.back() == '"') {
        return escaped.substr(1, escaped.size() - 2);
    }
    return escaped;
}

/**
 * Normalize JSON by adding quotes around unquoted keys.
 * Handles: {tool: "name"} -> {"tool": "name"}
 *
 * This handles common LLM output patterns where keys may not be quoted.
 * After normalization, the JSON can be parsed by nlohmann/json.
 */
std::string ToolCallingBridge::normalizeJson(const std::string& jsonStr) {
    std::string result;
    result.reserve(jsonStr.size() + 32);

    bool inString = false;
    for (size_t i = 0; i < jsonStr.size(); i++) {
        char c = jsonStr[i];

        // Track if we're inside a string
        if (c == '"' && (i == 0 || jsonStr[i-1] != '\\')) {
            inString = !inString;
            result += c;
            continue;
        }

        if (inString) {
            result += c;
            continue;
        }

        // Look for unquoted keys: { key: or , key:
        if ((c == '{' || c == ',') && i + 1 < jsonStr.size()) {
            result += c;
            // Skip whitespace
            size_t j = i + 1;
            while (j < jsonStr.size() && (jsonStr[j] == ' ' || jsonStr[j] == '\t' || jsonStr[j] == '\n')) {
                result += jsonStr[j];
                j++;
            }
            // Check if next is an unquoted identifier followed by colon
            if (j < jsonStr.size() && jsonStr[j] != '"' && jsonStr[j] != '{' && jsonStr[j] != '[') {
                size_t keyStart = j;
                while (j < jsonStr.size() && jsonStr[j] != ':' && jsonStr[j] != ' ' && jsonStr[j] != '\t') {
                    j++;
                }
                if (j < jsonStr.size()) {
                    // Skip whitespace to find colon
                    size_t keyEnd = j;
                    while (j < jsonStr.size() && (jsonStr[j] == ' ' || jsonStr[j] == '\t')) j++;
                    if (j < jsonStr.size() && jsonStr[j] == ':') {
                        // This is an unquoted key - add quotes
                        result += '"';
                        result += jsonStr.substr(keyStart, keyEnd - keyStart);
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
    // Find tool call tags (primary format)
    size_t tagStart = llmOutput.find(TOOL_CALL_START_TAG);

    // If no <tool_call> tag, check for alternate format: <tool_name {json}>
    // Some smaller models use the tool name as the tag instead of <tool_call>
    bool usingAlternateFormat = false;
    std::string alternateToolName;
    
    if (tagStart == std::string::npos) {
        // Look for pattern: <word followed by space/{ and JSON
        size_t ltPos = 0;
        while ((ltPos = llmOutput.find('<', ltPos)) != std::string::npos) {
            size_t nameStart = ltPos + 1;
            size_t nameEnd = nameStart;
            while (nameEnd < llmOutput.size() && 
                   (std::isalnum(static_cast<unsigned char>(llmOutput[nameEnd])) || 
                    llmOutput[nameEnd] == '_' || llmOutput[nameEnd] == '-')) {
                nameEnd++;
            }
            
            if (nameEnd > nameStart) {
                std::string tagName = llmOutput.substr(nameStart, nameEnd - nameStart);
                
                // Skip common HTML-like tags
                if (tagName != "p" && tagName != "br" && tagName != "div" && 
                    tagName != "span" && tagName != "a" && tagName.length() > 2) {
                    
                    size_t jsonStartCheck = nameEnd;
                    while (jsonStartCheck < llmOutput.size() && 
                           (llmOutput[jsonStartCheck] == ' ' || llmOutput[jsonStartCheck] == '\t' || 
                            llmOutput[jsonStartCheck] == '\n' || llmOutput[jsonStartCheck] == '>')) {
                        jsonStartCheck++;
                    }
                    
                    if (jsonStartCheck < llmOutput.size() && llmOutput[jsonStartCheck] == '{') {
                        tagStart = ltPos;
                        usingAlternateFormat = true;
                        alternateToolName = tagName;
                        break;
                    }
                }
            }
            ltPos++;
        }
    }

    if (tagStart == std::string::npos) {
        // No tool call found - return clean text with hasToolCall = false
        json result;
        result["hasToolCall"] = false;
        result["cleanText"] = llmOutput;
        return result.dump();
    }

    // Find JSON start position
    size_t jsonStart;
    if (usingAlternateFormat) {
        jsonStart = tagStart + 1 + alternateToolName.length();
        while (jsonStart < llmOutput.size() && 
               (llmOutput[jsonStart] == ' ' || llmOutput[jsonStart] == '\t' || 
                llmOutput[jsonStart] == '\n' || llmOutput[jsonStart] == '>')) {
            jsonStart++;
        }
    } else {
        jsonStart = tagStart + strlen(TOOL_CALL_START_TAG);
    }
    
    // Find end tag (only for standard format)
    size_t tagEnd = usingAlternateFormat ? std::string::npos : llmOutput.find(TOOL_CALL_END_TAG, jsonStart);
    bool hasClosingTag = (tagEnd != std::string::npos);

    if (!hasClosingTag) {
        // No closing tag - find JSON by matching braces
        // This handles models that output: <tool_call>{"tool": "name", ...}
        // without the closing </tool_call>
        std::string jsonPart = llmOutput.substr(jsonStart);
        int braceCount = 0;
        bool inStr = false;
        size_t jsonEndIndex = std::string::npos;

        for (size_t i = 0; i < jsonPart.size(); i++) {
            char c = jsonPart[i];
            
            // Track string boundaries to ignore braces inside strings
            if (c == '"' && (i == 0 || jsonPart[i-1] != '\\')) {
                inStr = !inStr;
            }
            
            if (!inStr) {
                if (c == '{') braceCount++;
                else if (c == '}') {
                    braceCount--;
                    if (braceCount == 0) {
                        jsonEndIndex = i + 1;
                        break;
                    }
                }
            }
        }

        if (jsonEndIndex == std::string::npos) {
            // Can't find valid JSON object
            json result;
            result["hasToolCall"] = false;
            result["cleanText"] = llmOutput;
            return result.dump();
        }
        tagEnd = jsonStart + jsonEndIndex;
    }

    // Extract JSON between tags
    std::string toolJsonStr = llmOutput.substr(jsonStart, tagEnd - jsonStart);
    
    // Normalize JSON (handle unquoted keys from LLMs)
    std::string normalizedJson = normalizeJson(toolJsonStr);

    // Parse with nlohmann/json
    json toolJson;
    try {
        toolJson = json::parse(normalizedJson);
    } catch (const json::parse_error& e) {
        // JSON parsing failed - return as no tool call
        json result;
        result["hasToolCall"] = false;
        result["cleanText"] = llmOutput;
        return result.dump();
    }

    // Extract tool name (try "tool" first, then "name", then use alternate format tag name)
    std::string toolName;
    if (toolJson.contains("tool") && toolJson["tool"].is_string()) {
        toolName = toolJson["tool"].get<std::string>();
    } else if (toolJson.contains("name") && toolJson["name"].is_string()) {
        toolName = toolJson["name"].get<std::string>();
    } else if (usingAlternateFormat && !alternateToolName.empty()) {
        // Use the tag name as tool name (e.g., <search_restaurants {args}> -> "search_restaurants")
        toolName = alternateToolName;
    } else {
        // Could not find tool name
        json result;
        result["hasToolCall"] = false;
        result["cleanText"] = llmOutput;
        return result.dump();
    }

    // Extract arguments (try "arguments" first, then "params")
    // For alternate format without explicit arguments, the JSON itself might be the arguments
    json arguments = json::object();
    if (toolJson.contains("arguments") && toolJson["arguments"].is_object()) {
        arguments = toolJson["arguments"];
    } else if (toolJson.contains("params") && toolJson["params"].is_object()) {
        arguments = toolJson["params"];
    } else if (usingAlternateFormat && !toolJson.contains("tool") && !toolJson.contains("name")) {
        // In alternate format like <search_restaurants {"query": "food"}>,
        // the entire JSON is the arguments
        arguments = toolJson;
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

    // Build JSON response using nlohmann/json
    json result;
    result["hasToolCall"] = true;
    result["cleanText"] = cleanText;
    result["toolName"] = toolName;
    result["argumentsJson"] = arguments;
    result["callId"] = 0;

    return result.dump();
}

} // namespace bridges
} // namespace runanywhere
