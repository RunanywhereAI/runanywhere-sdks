//
//  ToolCallParser.swift
//  RunAnywhere SDK
//
//  Internal parser for <tool_call> tags from LLM output.
//  Pure Swift implementation mirroring C++ ToolCallingBridge.cpp logic.
//
//  Handles edge cases:
//  - Missing closing </tool_call> tags (brace-matching fallback)
//  - Unquoted JSON keys from LLMs ({tool: "name"} → {"tool": "name"})
//  - Multiple key naming conventions ("tool"/"name", "arguments"/"params")
//

import Foundation

// MARK: - Tool Call Parser

/// Internal parser for extracting tool calls from LLM output.
/// Single source of truth for `<tool_call>` tag parsing in the Swift SDK.
internal enum ToolCallParser {

    // MARK: - Constants

    static let toolCallStartTag = "<tool_call>"
    static let toolCallEndTag = "</tool_call>"

    // MARK: - Parse Tool Call

    /// Parse LLM output for a tool call.
    ///
    /// Looks for `<tool_call>JSON</tool_call>` pattern in the output.
    /// Falls back to brace-matching if the closing tag is missing.
    ///
    /// - Parameter llmOutput: Raw LLM output text
    /// - Returns: Tuple of (cleanText, toolCall) where toolCall is nil if none found
    static func parseToolCall(from llmOutput: String) -> (text: String, toolCall: ToolCall?) {
        // Find <tool_call> tag
        guard let tagStartRange = llmOutput.range(of: toolCallStartTag) else {
            return (llmOutput, nil)
        }

        let jsonStartIndex = tagStartRange.upperBound

        // Find </tool_call> end tag
        let tagEndRange = llmOutput.range(of: toolCallEndTag, range: jsonStartIndex..<llmOutput.endIndex)
        let hasClosingTag = tagEndRange != nil

        let jsonEndIndex: String.Index

        if let tagEndRange = tagEndRange {
            jsonEndIndex = tagEndRange.lowerBound
        } else {
            // No closing tag - find JSON by matching braces
            // Handles models that output: <tool_call>{"tool": "name", ...} without closing tag
            guard let braceEnd = findMatchingBrace(in: llmOutput, from: jsonStartIndex) else {
                return (llmOutput, nil)
            }
            jsonEndIndex = braceEnd
        }

        // Extract JSON between tags
        let toolJsonStr = String(llmOutput[jsonStartIndex..<jsonEndIndex])

        // Normalize JSON (handle unquoted keys from LLMs)
        let normalizedJson = normalizeJson(toolJsonStr)

        // Parse JSON using ToolValue for type safety
        guard let toolValue = ToolValue.fromJSONString(normalizedJson),
              let jsonObject = toolValue.objectValue else {
            return (llmOutput, nil)
        }

        // Extract tool name (try "tool" first, then "name")
        let toolName: String
        if let name = jsonObject["tool"]?.stringValue {
            toolName = name
        } else if let name = jsonObject["name"]?.stringValue {
            toolName = name
        } else {
            return (llmOutput, nil)
        }

        // Extract arguments (try "arguments" first, then "params")
        let arguments: [String: ToolValue]
        if let args = jsonObject["arguments"]?.objectValue {
            arguments = args
        } else if let args = jsonObject["params"]?.objectValue {
            arguments = args
        } else {
            arguments = [:]
        }

        // Build clean text (everything except the tool call tags)
        let beforeTag = String(llmOutput[llmOutput.startIndex..<tagStartRange.lowerBound])
        let afterTag: String
        if let tagEndRange = tagEndRange {
            afterTag = String(llmOutput[tagEndRange.upperBound..<llmOutput.endIndex])
        } else {
            afterTag = String(llmOutput[jsonEndIndex..<llmOutput.endIndex])
        }

        let cleanText = (beforeTag + afterTag)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let toolCall = ToolCall(
            toolName: toolName,
            arguments: arguments,
            callId: "call_\(Int(Date().timeIntervalSince1970 * 1000))"
        )

        return (cleanText, toolCall)
    }

    // MARK: - Format Tools for Prompt

    /// Format tool definitions into a system prompt for the LLM.
    ///
    /// Creates instruction text describing available tools and the expected
    /// `<tool_call>` output format. Matches the TypeScript formatToolsForPrompt.
    ///
    /// - Parameter tools: Array of tool definitions
    /// - Returns: Formatted system prompt string
    static func formatToolsForPrompt(_ tools: [ToolDefinition]) -> String {
        guard !tools.isEmpty else { return "" }

        let toolDescriptions = tools.map { tool -> String in
            let params = tool.parameters
                .map { param in
                    "    - \(param.name) (\(param.type.rawValue)\(param.required ? ", required" : "")): \(param.description)"
                }
                .joined(separator: "\n")

            return "- \(tool.name): \(tool.description)\n  Parameters:\n\(params)"
        }

        return """
        You have access to these tools:

        \(toolDescriptions.joined(separator: "\n\n"))

        TOOL CALLING FORMAT - YOU MUST USE THIS EXACT FORMAT:
        When you need to use a tool, output ONLY this (no other text before or after):
        <tool_call>{"tool": "TOOL_NAME", "arguments": {"PARAM_NAME": "VALUE"}}</tool_call>

        EXAMPLE - If user asks "what's the weather in Paris":
        <tool_call>{"tool": "get_weather", "arguments": {"location": "Paris"}}</tool_call>

        RULES:
        1. For greetings or general chat, respond normally without tools
        2. When using a tool, output ONLY the <tool_call> tag, nothing else
        3. Use the exact parameter names shown in the tool definitions above
        """
    }

    // MARK: - Private Helpers

    /// Find the matching closing brace for a JSON object starting at the given index.
    /// Tracks string boundaries to ignore braces inside strings.
    ///
    /// - Parameters:
    ///   - string: The string to search in
    ///   - startIndex: The index to start searching from
    /// - Returns: The index after the matching closing brace, or nil if not found
    private static func findMatchingBrace(in string: String, from startIndex: String.Index) -> String.Index? {
        var braceCount = 0
        var inString = false
        var index = startIndex

        while index < string.endIndex {
            let char = string[index]
            let prevIndex = string.index(before: index)

            // Track string boundaries (ignore escaped quotes)
            if char == "\"" && (index == string.startIndex || string[prevIndex] != "\\") {
                inString.toggle()
            }

            if !inString {
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                    if braceCount == 0 {
                        return string.index(after: index)
                    }
                }
            }

            index = string.index(after: index)
        }

        return nil
    }

    /// Normalize JSON by adding quotes around unquoted keys.
    /// Handles common LLM output patterns: `{tool: "name"}` → `{"tool": "name"}`
    ///
    /// Direct port of C++ ToolCallingBridge::normalizeJson()
    ///
    /// - Parameter jsonStr: Raw JSON string possibly with unquoted keys
    /// - Returns: Normalized JSON string with all keys quoted
    static func normalizeJson(_ jsonStr: String) -> String {
        var result = ""
        result.reserveCapacity(jsonStr.count + 32)

        let chars = Array(jsonStr)
        var inString = false
        var i = 0

        while i < chars.count {
            let char = chars[i]

            // Track if we're inside a string
            if char == "\"" && (i == 0 || chars[i - 1] != "\\") {
                inString.toggle()
                result.append(char)
                i += 1
                continue
            }

            if inString {
                result.append(char)
                i += 1
                continue
            }

            // Look for unquoted keys: { key: or , key:
            if (char == "{" || char == ",") && i + 1 < chars.count {
                result.append(char)

                // Skip whitespace
                var nextIdx = i + 1
                while nextIdx < chars.count && (chars[nextIdx] == " " || chars[nextIdx] == "\t" || chars[nextIdx] == "\n") {
                    result.append(chars[nextIdx])
                    nextIdx += 1
                }

                // Check if next is an unquoted identifier followed by colon
                if nextIdx < chars.count && chars[nextIdx] != "\"" && chars[nextIdx] != "{" && chars[nextIdx] != "[" {
                    let keyStart = nextIdx
                    while nextIdx < chars.count && chars[nextIdx] != ":" && chars[nextIdx] != " " && chars[nextIdx] != "\t" {
                        nextIdx += 1
                    }

                    if nextIdx < chars.count {
                        let keyEnd = nextIdx
                        // Skip whitespace to find colon
                        while nextIdx < chars.count && (chars[nextIdx] == " " || chars[nextIdx] == "\t") {
                            nextIdx += 1
                        }
                        if nextIdx < chars.count && chars[nextIdx] == ":" {
                            // This is an unquoted key - add quotes
                            result.append("\"")
                            result.append(contentsOf: chars[keyStart..<keyEnd])
                            result.append("\"")
                            i = keyEnd // loop will increment
                            continue
                        }
                    }
                }

                i = nextIdx // loop will increment... but we already advanced
                continue
            }

            result.append(char)
            i += 1
        }

        return result
    }
}
