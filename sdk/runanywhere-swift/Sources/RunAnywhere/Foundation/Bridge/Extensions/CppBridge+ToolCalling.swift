//
//  CppBridge+ToolCalling.swift
//  RunAnywhere SDK
//
//  C++ bridge for tool calling functionality.
//
//  *** SINGLE SOURCE OF TRUTH FOR TOOL CALLING LOGIC ***
//  All parsing and prompt formatting is done in C++ (rac_tool_calling.h).
//  This bridge is a THIN WRAPPER - no parsing logic in Swift.
//
//  Platform SDKs handle ONLY:
//  - Tool registry (Swift closures)
//  - Tool execution (Swift async calls)
//

import Foundation
import CRACommons

// MARK: - Tool Calling Bridge

extension CppBridge {

    /// Tool calling bridge to C++ implementation
    public enum ToolCalling {

        // MARK: - Parse Tool Call (NO FALLBACK)

        /// Parse LLM output for tool calls using C++ implementation.
        ///
        /// *** THIS IS THE ONLY PARSING IMPLEMENTATION - NO SWIFT FALLBACK ***
        ///
        /// Handles all edge cases:
        /// - Missing closing tags (brace-matching)
        /// - Unquoted JSON keys ({tool: "name"} → {"tool": "name"})
        /// - Multiple key naming conventions
        /// - Tool name as key pattern
        ///
        /// - Parameter llmOutput: Raw LLM output text
        /// - Returns: Tuple of (cleanText, toolCall) where toolCall is nil if none found
        public static func parseToolCall(from llmOutput: String) -> (text: String, toolCall: ToolCall?) {
            var result = rac_tool_call_t()
            defer { rac_tool_call_free(&result) }

            let rc = rac_tool_call_parse(llmOutput, &result)

            guard rc == RAC_SUCCESS, result.has_tool_call == RAC_TRUE else {
                // No tool call found - return clean text
                let cleanText: String
                if let cleanPtr = result.clean_text {
                    cleanText = String(cString: cleanPtr)
                } else {
                    cleanText = llmOutput
                }
                return (cleanText, nil)
            }

            // Extract tool name
            guard let toolNamePtr = result.tool_name else {
                return (llmOutput, nil)
            }
            let toolName = String(cString: toolNamePtr)

            // Extract arguments JSON
            let argsJson: String
            if let argsPtr = result.arguments_json {
                argsJson = String(cString: argsPtr)
            } else {
                argsJson = "{}"
            }

            // Extract clean text
            let cleanText: String
            if let cleanPtr = result.clean_text {
                cleanText = String(cString: cleanPtr)
            } else {
                cleanText = ""
            }

            // Parse arguments JSON to [String: ToolValue]
            let arguments = parseArgumentsJson(argsJson)

            return (cleanText, ToolCall(
                toolName: toolName,
                arguments: arguments,
                callId: "call_\(result.call_id)"
            ))
        }

        // MARK: - Format Tools for Prompt (NO FALLBACK)

        /// Format tool definitions into a system prompt using C++ implementation.
        ///
        /// Creates instruction text describing available tools and the expected
        /// tool call output format.
        ///
        /// - Parameters:
        ///   - tools: Array of tool definitions
        ///   - format: Tool call format to use (default: .default)
        /// - Returns: Formatted system prompt string
        public static func formatToolsForPrompt(
            _ tools: [ToolDefinition],
            format: ToolCallFormat = .default
        ) -> String {
            guard !tools.isEmpty else { return "" }

            let toolsJson = serializeToolsToJson(tools)
            var promptPtr: UnsafeMutablePointer<CChar>?
            defer { if let p = promptPtr { rac_free(p) } }

            let cFormat = rac_tool_call_format_t(rawValue: UInt32(format.rawValue))
            let rc = rac_tool_call_format_prompt_json_with_format(toolsJson, cFormat, &promptPtr)
            guard rc == RAC_SUCCESS, let ptr = promptPtr else {
                return ""
            }

            return String(cString: ptr)
        }

        // MARK: - Build Initial Prompt (NO FALLBACK)

        /// Build the initial prompt with tools and user query using C++ implementation.
        ///
        /// Combines system prompt, tool instructions, and user prompt.
        ///
        /// - Parameters:
        ///   - userPrompt: The user's question/request
        ///   - tools: Array of tool definitions
        ///   - options: Tool calling options
        /// - Returns: Complete formatted prompt
        public static func buildInitialPrompt(
            userPrompt: String,
            tools: [ToolDefinition],
            options: ToolCallingOptions
        ) -> String {
            let toolsJson = serializeToolsToJson(tools)
            var promptPtr: UnsafeMutablePointer<CChar>?
            defer { if let p = promptPtr { rac_free(p) } }

            // Create C options struct
            var cOptions = rac_tool_calling_options_t()
            cOptions.max_tool_calls = Int32(options.maxToolCalls)
            cOptions.auto_execute = options.autoExecute ? RAC_TRUE : RAC_FALSE
            cOptions.temperature = options.temperature ?? 0.7
            cOptions.max_tokens = Int32(options.maxTokens ?? 1024)
            cOptions.replace_system_prompt = options.replaceSystemPrompt ? RAC_TRUE : RAC_FALSE
            cOptions.keep_tools_available = options.keepToolsAvailable ? RAC_TRUE : RAC_FALSE
            cOptions.format = rac_tool_call_format_t(rawValue: UInt32(options.format.rawValue))

            // Handle system prompt
            if let systemPrompt = options.systemPrompt {
                return systemPrompt.withCString { sysPtr in
                    cOptions.system_prompt = sysPtr
                    return toolsJson.withCString { toolsPtr in
                        return userPrompt.withCString { userPtr in
                            let rc = rac_tool_call_build_initial_prompt(userPtr, toolsPtr, &cOptions, &promptPtr)
                            guard rc == RAC_SUCCESS, let ptr = promptPtr else {
                                return userPrompt
                            }
                            return String(cString: ptr)
                        }
                    }
                }
            } else {
                cOptions.system_prompt = nil
                let rc = rac_tool_call_build_initial_prompt(userPrompt, toolsJson, &cOptions, &promptPtr)
                guard rc == RAC_SUCCESS, let ptr = promptPtr else {
                    return userPrompt
                }
                return String(cString: ptr)
            }
        }

        // MARK: - Build Follow-up Prompt (NO FALLBACK)

        /// Build follow-up prompt after tool execution using C++ implementation.
        ///
        /// - Parameters:
        ///   - originalPrompt: The original user prompt
        ///   - toolsPrompt: The formatted tools prompt (nil if not keeping tools)
        ///   - toolName: Name of the tool that was executed
        ///   - toolResultJson: JSON string of the tool result
        ///   - keepToolsAvailable: Whether to include tool definitions
        /// - Returns: Follow-up prompt string
        public static func buildFollowupPrompt(
            originalPrompt: String,
            toolsPrompt: String?,
            toolName: String,
            toolResultJson: String,
            keepToolsAvailable: Bool
        ) -> String {
            var promptPtr: UnsafeMutablePointer<CChar>?
            defer { if let p = promptPtr { rac_free(p) } }

            let toolsPromptPtr = toolsPrompt?.withCString { UnsafePointer($0) }

            let rc = rac_tool_call_build_followup_prompt(
                originalPrompt,
                toolsPromptPtr,
                toolName,
                toolResultJson,
                keepToolsAvailable ? RAC_TRUE : RAC_FALSE,
                &promptPtr
            )
            guard rc == RAC_SUCCESS, let ptr = promptPtr else {
                return ""
            }

            return String(cString: ptr)
        }

        // MARK: - JSON Normalization (NO FALLBACK)

        /// Normalize JSON by adding quotes around unquoted keys using C++ implementation.
        ///
        /// Handles common LLM output patterns: `{tool: "name"}` → `{"tool": "name"}`
        ///
        /// - Parameter jsonStr: Raw JSON string possibly with unquoted keys
        /// - Returns: Normalized JSON string with all keys quoted
        public static func normalizeJson(_ jsonStr: String) -> String {
            var normalizedPtr: UnsafeMutablePointer<CChar>?
            defer { if let p = normalizedPtr { rac_free(p) } }

            let rc = rac_tool_call_normalize_json(jsonStr, &normalizedPtr)
            guard rc == RAC_SUCCESS, let ptr = normalizedPtr else {
                return jsonStr
            }

            return String(cString: ptr)
        }

        // MARK: - Private Helpers

        /// Parse arguments JSON string to [String: ToolValue] dictionary
        private static func parseArgumentsJson(_ json: String) -> [String: ToolValue] {
            guard let data = json.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return [:]
            }
            return dict.mapValues { anyToToolValue($0) }
        }

        /// Convert Any to ToolValue
        private static func anyToToolValue(_ value: Any) -> ToolValue {
            switch value {
            case let str as String:
                return .string(str)
            case let num as NSNumber:
                // Check if it's a boolean
                if CFGetTypeID(num) == CFBooleanGetTypeID() {
                    return .bool(num.boolValue)
                }
                return .number(num.doubleValue)
            case let arr as [Any]:
                return .array(arr.map { anyToToolValue($0) })
            case let dict as [String: Any]:
                return .object(dict.mapValues { anyToToolValue($0) })
            case is NSNull:
                return .null
            default:
                return .null
            }
        }

        /// Serialize tool definitions to JSON array string
        private static func serializeToolsToJson(_ tools: [ToolDefinition]) -> String {
            let jsonArray = tools.map { tool -> [String: Any] in
                [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": tool.parameters.map { param -> [String: Any] in
                        var paramDict: [String: Any] = [
                            "name": param.name,
                            "type": param.type.rawValue,
                            "description": param.description,
                            "required": param.required
                        ]
                        if let enumValues = param.enumValues {
                            paramDict["enumValues"] = enumValues
                        }
                        return paramDict
                    }
                ]
            }

            guard let data = try? JSONSerialization.data(withJSONObject: jsonArray),
                  let json = String(data: data, encoding: .utf8) else {
                return "[]"
            }
            return json
        }
    }
}
