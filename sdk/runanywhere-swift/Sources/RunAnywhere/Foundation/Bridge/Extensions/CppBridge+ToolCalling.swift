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

import CRACommons
import Foundation

private enum ToolCallingGeneratedProtoABI {
    static let parseName = "rac_tool_call_parse_proto"
    static let formatPromptName = "rac_tool_call_format_prompt_proto"
    static let validateName = "rac_tool_call_validate_proto"

    static let parse = NativeProtoABI.load(parseName, as: NativeProtoABI.ProtoRequest.self)
    static let formatPrompt = NativeProtoABI.load(formatPromptName, as: NativeProtoABI.ProtoRequest.self)
    static let validate = NativeProtoABI.load(validateName, as: NativeProtoABI.ProtoRequest.self)
}

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
        public static func parseToolCall(
            from llmOutput: String,
            options: RAToolCallingOptions = RAToolCallingOptions.defaults()
        ) throws -> (text: String, toolCall: RAToolCall?) {
            var request = RAToolParseRequest()
            request.text = llmOutput
            request.options = bridgeOptions(options)

            let result = try NativeProtoABI.invoke(
                request,
                symbol: ToolCallingGeneratedProtoABI.parse,
                symbolName: ToolCallingGeneratedProtoABI.parseName,
                responseType: RAToolParseResult.self
            )
            try throwIfError(result.errorCode, message: result.errorMessage)

            guard result.hasToolCall_p, let firstCall = result.toolCalls.first else {
                return (result.remainingText.isEmpty ? llmOutput : result.remainingText, nil)
            }

            return (result.remainingText, hydrateArguments(firstCall))
        }

        // MARK: - Format Tools for Prompt (NO FALLBACK)

        /// Format tool definitions into a system prompt using C++ implementation.
        ///
        /// Creates instruction text describing available tools and the expected
        /// tool call output format.
        ///
        /// - Parameters:
        ///   - tools: Array of generated tool definitions
        ///   - format: Tool call format name (e.g., "default", "lfm2").
        /// - Returns: Formatted system prompt string
        public static func formatToolsForPrompt(
            _ tools: [RAToolDefinition],
            format: String = "default"
        ) throws -> String {
            guard !tools.isEmpty else { return "" }

            var options = RAToolCallingOptions.defaults()
            options.formatHint = format
            options.format = protoFormatName(from: format)
            let request = makePromptFormatRequest(
                userPrompt: "",
                tools: tools,
                options: options
            )
            let result = try formatPrompt(request)
            return try formattedPrompt(from: result)
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
            tools: [RAToolDefinition],
            options: RAToolCallingOptions
        ) throws -> String {
            guard !tools.isEmpty else { return userPrompt }

            let request = makePromptFormatRequest(
                userPrompt: userPrompt,
                tools: tools,
                options: options
            )
            let result = try formatPrompt(request)
            return try formattedPrompt(from: result)
        }

        // MARK: - Build Follow-up Prompt (NO FALLBACK)

        /// Build follow-up prompt after tool execution using C++ implementation.
        ///
        /// - Parameters:
        ///   - originalPrompt: The original user prompt
        ///   - tools: Available generated tool definitions.
        ///   - toolResult: Generated tool execution result.
        ///   - options: Generated tool-calling options.
        /// - Returns: Follow-up prompt string
        public static func buildFollowupPrompt(
            originalPrompt: String,
            tools: [RAToolDefinition],
            toolResult: RAToolResult,
            options: RAToolCallingOptions
        ) throws -> String {
            let request = makePromptFormatRequest(
                userPrompt: originalPrompt,
                tools: tools,
                options: options,
                toolResults: [toolResult]
            )
            let result = try formatPrompt(request)
            return try formattedPrompt(from: result)
        }

        public static func validateToolCall(
            _ toolCall: RAToolCall,
            tools: [RAToolDefinition],
            options: RAToolCallingOptions
        ) throws -> RAToolCallValidationResult {
            let request = makeValidationRequest(
                toolCall: toolCall,
                tools: tools,
                options: options
            )
            return try NativeProtoABI.invoke(
                request,
                symbol: ToolCallingGeneratedProtoABI.validate,
                symbolName: ToolCallingGeneratedProtoABI.validateName,
                responseType: RAToolCallValidationResult.self
            )
        }

        static func makePromptFormatRequest(
            userPrompt: String,
            tools: [RAToolDefinition],
            options: RAToolCallingOptions,
            toolResults: [RAToolResult] = []
        ) -> RAToolPromptFormatRequest {
            var request = RAToolPromptFormatRequest()
            request.userPrompt = userPrompt
            request.options = bridgeOptions(options, tools: tools)
            request.toolResults = toolResults
            return request
        }

        static func makeValidationRequest(
            toolCall: RAToolCall,
            tools: [RAToolDefinition],
            options: RAToolCallingOptions
        ) -> RAToolCallValidationRequest {
            var request = RAToolCallValidationRequest()
            request.toolCall = toolCall
            request.options = bridgeOptions(options, tools: tools)
            return request
        }

        static func bridgeOptions(
            _ options: RAToolCallingOptions,
            tools: [RAToolDefinition]? = nil
        ) -> RAToolCallingOptions {
            var bridged = options
            if let tools {
                bridged.tools = tools
            }
            let formatName = options.resolvedFormatName
            bridged.formatHint = formatName
            bridged.format = protoFormatName(from: formatName)
            return bridged
        }

        // MARK: - Private Helpers

        private static func formatPrompt(
            _ request: RAToolPromptFormatRequest
        ) throws -> RAToolPromptFormatResult {
            try NativeProtoABI.invoke(
                request,
                symbol: ToolCallingGeneratedProtoABI.formatPrompt,
                symbolName: ToolCallingGeneratedProtoABI.formatPromptName,
                responseType: RAToolPromptFormatResult.self
            )
        }

        private static func formattedPrompt(from result: RAToolPromptFormatResult) throws -> String {
            try throwIfError(result.errorCode, message: result.errorMessage)
            return result.formattedPrompt
        }

        private static func throwIfError(_ errorCode: Int32, message: String) throws {
            guard errorCode == RAC_SUCCESS else {
                throw SDKException(
                    code: .processingFailed,
                    message: message.isEmpty ? "Tool calling proto request failed: \(errorCode)" : message,
                    category: .internal
                )
            }
        }

        private static func hydrateArguments(_ toolCall: RAToolCall) -> RAToolCall {
            // IDL-13: typed `arguments` map deleted; `argumentsJson` is canonical.
            return toolCall
        }

        private static func protoFormatName(from formatName: String) -> RAToolCallFormatName {
            switch formatName.lowercased() {
            case "lfm2", "lfm", "liquid", "pythonic", "hermes":
                return .pythonic
            case "openai", "openai_functions", "openai-functions":
                return .openaiFunctions
            case "xml":
                return .xml
            case "native":
                return .native
            case "json", "default", "auto":
                return .json
            default:
                return .json
            }
        }
    }
}
