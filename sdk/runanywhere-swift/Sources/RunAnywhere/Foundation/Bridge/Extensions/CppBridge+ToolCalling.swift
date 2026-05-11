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

// MARK: - Tool Calling Bridge

extension CppBridge {

    /// Tool calling bridge to C++ implementation
    public enum ToolCalling {

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
