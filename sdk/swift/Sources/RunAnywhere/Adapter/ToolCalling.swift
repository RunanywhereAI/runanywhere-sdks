// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import Foundation

/// Tool / function-call scaffolding. Runs in Swift on top of `ChatSession`:
/// formats tool definitions into the system prompt, collects generated
/// text, and parses `<tool_call>{...}</tool_call>` blocks back into
/// structured `ToolCall` values. This mirrors how the legacy SDK handled
/// tool calling before `ra_llm_tool_calling` becomes a native C primitive.

public struct ToolParameter: Sendable, Codable {
    public let name: String
    public let type: String
    public let description: String
    public let required: Bool
    public init(name: String, type: String, description: String,
                required: Bool = true) {
        self.name = name; self.type = type
        self.description = description; self.required = required
    }
}

public struct ToolDefinition: Sendable {
    public let name: String
    public let description: String
    public let parameters: [ToolParameter]
    public init(name: String, description: String, parameters: [ToolParameter]) {
        self.name = name; self.description = description
        self.parameters = parameters
    }
}

public struct ToolCall: @unchecked Sendable {
    public let name: String
    public let arguments: [String: Any]
    public init(name: String, arguments: [String: Any]) {
        self.name = name; self.arguments = arguments
    }
}

public enum ToolCallingError: Error {
    case parseFailed(String)
    case malformedJSON(String)
}

public enum ToolFormatter {

    /// Formats tool definitions into a system-prompt fragment that tells
    /// the model how to invoke them. ChatML / Qwen style — compatible with
    /// most instruction-tuned models.
    public static func systemPrompt(for tools: [ToolDefinition]) -> String {
        guard !tools.isEmpty else { return "" }
        var out = "You have access to the following tools:\n\n"
        for tool in tools {
            let argSchema = tool.parameters.map { p in
                let req = p.required ? "" : " (optional)"
                return "    \"\(p.name)\": <\(p.type)>  // \(p.description)\(req)"
            }.joined(separator: "\n")
            out += """
            \(tool.name): \(tool.description)
            Arguments:
            {
            \(argSchema)
            }

            """
        }
        out += """

        To invoke a tool, reply with EXACTLY:
        <tool_call>{"name":"<tool_name>","arguments":{<args_json>}}</tool_call>

        Only output the tool call and nothing else when you use a tool.
        """
        return out
    }

    /// Parses tool-call blocks out of model output. Returns any detected
    /// calls; silently ignores malformed blocks to avoid breaking the
    /// agent loop on partial output.
    public static func parseToolCalls(from text: String) throws -> [ToolCall] {
        var calls: [ToolCall] = []
        let pattern = #"<tool_call>(.*?)</tool_call>"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        for match in matches where match.numberOfRanges > 1 {
            guard let jsonRange = Range(match.range(at: 1), in: text) else { continue }
            let jsonString = String(text[jsonRange])
            guard let data = jsonString.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = obj["name"] as? String,
                  let args = obj["arguments"] as? [String: Any] else {
                continue
            }
            calls.append(ToolCall(name: name, arguments: args))
        }
        return calls
    }
}

/// High-level tool-calling agent built on ChatSession. Invoke `send`
/// with a user message, get either a plain assistant response or a
/// list of pending tool calls. Caller executes the tools and passes
/// their results back via `continueAfter(toolResults:)`.
public final class ToolCallingAgent: @unchecked Sendable {
    private let chat: ChatSession
    private let tools: [ToolDefinition]
    private var history: [ChatSession.Message] = []

    public init(modelId: String, modelPath: String,
                tools: [ToolDefinition],
                systemPrompt: String = "") throws {
        self.tools = tools
        let toolPrompt = ToolFormatter.systemPrompt(for: tools)
        let combined = [systemPrompt, toolPrompt]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        self.chat = try ChatSession(
            modelId: modelId,
            modelPath: modelPath,
            systemPrompt: combined)
    }

    public enum Reply: Sendable {
        case assistant(String)
        case toolCalls([ToolCall])
    }

    public func send(userMessage: String) async throws -> Reply {
        history.append(.user(userMessage))
        let responseText = try await chat.generateText(messages: history)
        history.append(.assistant(responseText))

        let calls = try ToolFormatter.parseToolCalls(from: responseText)
        if !calls.isEmpty {
            return .toolCalls(calls)
        }
        return .assistant(responseText)
    }

    public func continueAfter(toolResults: [(name: String, result: String)])
        async throws -> Reply
    {
        let blob = toolResults.map { "Tool `\($0.name)` returned:\n\($0.result)" }
            .joined(separator: "\n\n")
        history.append(.tool(blob))
        let responseText = try await chat.generateText(messages: history)
        history.append(.assistant(responseText))

        let calls = try ToolFormatter.parseToolCalls(from: responseText)
        if !calls.isEmpty {
            return .toolCalls(calls)
        }
        return .assistant(responseText)
    }

    public func resetHistory() throws {
        history.removeAll()
        try chat.resetHistory()
    }
}
