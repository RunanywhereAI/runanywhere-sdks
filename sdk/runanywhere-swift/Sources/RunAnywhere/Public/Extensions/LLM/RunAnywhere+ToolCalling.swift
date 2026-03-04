//
//  RunAnywhere+ToolCalling.swift
//  RunAnywhere SDK
//
//  Public API for tool calling (function calling) with LLMs.
//  Allows LLMs to request external actions (API calls, device functions, etc.)
//
//  ARCHITECTURE:
//  - CppBridge.ToolCalling: C++ bridge for parsing <tool_call> tags (SINGLE SOURCE OF TRUTH)
//  - This file: Tool registration, executor storage, orchestration
//  - Orchestration: generate → parse (C++) → execute → loop
//
//  *** ALL PARSING LOGIC IS IN C++ (rac_tool_calling.h) - NO SWIFT FALLBACKS ***
//
//  Mirrors sdk/runanywhere-react-native RunAnywhere+ToolCalling.ts
//

import Foundation

// MARK: - Tool Registry (Thread-safe)

/// Actor-based tool registry for thread-safe tool registration and lookup.
private actor ToolRegistry {
    static let shared = ToolRegistry()

    private var tools: [String: RegisteredTool] = [:]

    func register(_ definition: ToolDefinition, executor: @escaping ToolExecutor) {
        tools[definition.name] = RegisteredTool(definition: definition, executor: executor)
    }

    func unregister(_ toolName: String) {
        tools.removeValue(forKey: toolName)
    }

    func getAll() -> [ToolDefinition] {
        tools.values.map(\.definition)
    }

    func get(_ toolName: String) -> RegisteredTool? {
        tools[toolName]
    }

    func clear() {
        tools.removeAll()
    }
}

// MARK: - Tool Calling Extension

public extension RunAnywhere {

    // MARK: - Tool Registration

    /// Register a tool that the LLM can use.
    ///
    /// Tools are stored in-memory and available for all subsequent `generateWithTools` calls.
    /// Executors run in Swift and have full access to Swift/iOS APIs (networking, device, etc.).
    ///
    /// Example:
    /// ```swift
    /// RunAnywhere.registerTool(
    ///     ToolDefinition(
    ///         name: "get_weather",
    ///         description: "Gets current weather for a location",
    ///         parameters: [
    ///             ToolParameter(name: "location", type: .string, description: "City name")
    ///         ]
    ///     )
    /// ) { args in
    ///     let location = args["location"] as? String ?? "Unknown"
    ///     // Call weather API...
    ///     return ["temperature": 72, "condition": "Sunny"]
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - definition: Tool definition (name, description, parameters)
    ///   - executor: Async closure that executes the tool
    static func registerTool(
        _ definition: ToolDefinition,
        executor: @escaping ToolExecutor
    ) async {
        await ToolRegistry.shared.register(definition, executor: executor)
    }

    /// Unregister a tool by name.
    ///
    /// - Parameter toolName: The name of the tool to remove
    static func unregisterTool(_ toolName: String) async {
        await ToolRegistry.shared.unregister(toolName)
    }

    /// Get all registered tool definitions.
    ///
    /// - Returns: Array of registered tool definitions
    static func getRegisteredTools() async -> [ToolDefinition] {
        await ToolRegistry.shared.getAll()
    }

    /// Clear all registered tools.
    static func clearTools() async {
        await ToolRegistry.shared.clear()
    }

    // MARK: - Tool Execution

    /// Execute a tool call.
    ///
    /// Looks up the tool in the registry and invokes its executor with the provided arguments.
    /// Returns a `ToolResult` with success/failure status.
    ///
    /// - Parameter toolCall: The tool call to execute
    /// - Returns: Result of the tool execution
    static func executeTool(_ toolCall: ToolCall) async -> ToolResult {
        guard let tool = await ToolRegistry.shared.get(toolCall.toolName) else {
            return ToolResult(
                toolName: toolCall.toolName,
                success: false,
                error: "Unknown tool: \(toolCall.toolName)",
                callId: toolCall.callId
            )
        }

        do {
            let result = try await tool.executor(toolCall.arguments)
            return ToolResult(
                toolName: toolCall.toolName,
                success: true,
                result: result,
                callId: toolCall.callId
            )
        } catch {
            return ToolResult(
                toolName: toolCall.toolName,
                success: false,
                error: error.localizedDescription,
                callId: toolCall.callId
            )
        }
    }

    // MARK: - Generate with Tools

    /// Generates a response with tool calling support.
    ///
    /// Orchestrates a generate → parse → execute → loop cycle:
    /// 1. Builds a system prompt describing available tools
    /// 2. Generates LLM response
    /// 3. Parses output for `<tool_call>` tags
    /// 4. If tool call found and `autoExecute` is true, executes and continues
    /// 5. Repeats until no more tool calls or `maxToolCalls` reached
    ///
    /// - Parameters:
    ///   - prompt: The user's prompt
    ///   - options: Tool calling options (tools, maxToolCalls, autoExecute, etc.)
    /// - Returns: Result containing final text, all tool calls made, and their results
    static func generateWithTools(
        _ prompt: String,
        options: ToolCallingOptions? = nil
    ) async throws -> ToolCallingResult {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }
        try await ensureServicesReady()

        let opts = options ?? ToolCallingOptions()
        let registeredTools = await ToolRegistry.shared.getAll()
        let tools = opts.tools ?? registeredTools

        let systemPrompt = buildToolSystemPrompt(tools: tools, options: opts)
        var fullPrompt = systemPrompt.isEmpty ? prompt : "\(systemPrompt)\n\nUser: \(prompt)"

        var allToolCalls: [ToolCall] = []
        var allToolResults: [ToolResult] = []
        var finalText = ""

        for _ in 0..<opts.maxToolCalls {
            let responseText = try await generateAndCollect(
                fullPrompt, temperature: opts.temperature, maxTokens: opts.maxTokens
            )

            // Parse using C++ implementation (SINGLE SOURCE OF TRUTH - NO FALLBACK)
            let (text, toolCall) = CppBridge.ToolCalling.parseToolCall(from: responseText)
            finalText = text

            guard let toolCall = toolCall else { break }
            allToolCalls.append(toolCall)

            if !opts.autoExecute {
                return ToolCallingResult(
                    text: finalText, toolCalls: allToolCalls, toolResults: [], isComplete: false
                )
            }

            let result = await executeTool(toolCall)
            allToolResults.append(result)

            fullPrompt = buildFollowUpPrompt(
                prompt: prompt,
                systemPrompt: systemPrompt,
                toolCall: toolCall,
                result: result,
                keepToolsAvailable: opts.keepToolsAvailable
            )
        }

        return ToolCallingResult(
            text: finalText,
            toolCalls: allToolCalls,
            toolResults: allToolResults,
            isComplete: true
        )
    }

    /// Builds the system prompt with tool definitions using C++ implementation.
    private static func buildToolSystemPrompt(
        tools: [ToolDefinition],
        options: ToolCallingOptions
    ) -> String {
        // Use C++ implementation for prompt formatting (SINGLE SOURCE OF TRUTH)
        // Pass the format from options to generate model-specific instructions
        let toolsPrompt = CppBridge.ToolCalling.formatToolsForPrompt(tools, format: options.format)

        if options.replaceSystemPrompt, let userPrompt = options.systemPrompt {
            return userPrompt
        } else if let userPrompt = options.systemPrompt {
            return "\(userPrompt)\n\n\(toolsPrompt)"
        } else {
            return toolsPrompt
        }
    }

    /// Builds the follow-up prompt after a tool execution.
    private static func buildFollowUpPrompt(
        prompt: String,
        systemPrompt: String,
        toolCall: ToolCall,
        result: ToolResult,
        keepToolsAvailable: Bool
    ) -> String {
        let resultData: [String: ToolValue] = result.success
            ? (result.result ?? [:])
            : ["error": .string(result.error ?? "Unknown error")]
        let resultJson = ToolValue.object(resultData).toJSONString() ?? "{}"

        if keepToolsAvailable {
            return """
            \(systemPrompt)

            User: \(prompt)

            You previously used the \(toolCall.toolName) tool and received:
            \(resultJson)

            Based on this tool result, either use another tool if needed, or provide a helpful response.
            """
        } else {
            return """
            The user asked: "\(prompt)"

            You used the \(toolCall.toolName) tool and received this data:
            \(resultJson)

            Now provide a helpful, natural response to the user based on this information.
            """
        }
    }

    /// Continue generation after manual tool execution.
    ///
    /// Use this when `autoExecute` is false. After receiving a `ToolCallingResult`
    /// with `isComplete: false`, execute the tool yourself, then call this to continue.
    ///
    /// - Parameters:
    ///   - previousPrompt: The original user prompt
    ///   - toolCall: The tool call that was executed
    ///   - toolResult: The result of executing the tool
    ///   - options: Tool calling options for the continuation
    /// - Returns: Result of the continued generation
    static func continueWithToolResult(
        previousPrompt: String,
        toolCall: ToolCall,
        toolResult: ToolResult,
        options: ToolCallingOptions? = nil
    ) async throws -> ToolCallingResult {
        let resultJson: String
        if toolResult.success, let result = toolResult.result,
           let jsonData = try? JSONSerialization.data(withJSONObject: result),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            resultJson = jsonString
        } else {
            resultJson = "Error: \(toolResult.error ?? "Unknown error")"
        }

        let continuedPrompt = """
            \(previousPrompt)

            Tool Result for \(toolCall.toolName): \(resultJson)

            Based on the tool result, please provide your response:
            """

        let continuationOptions = ToolCallingOptions(
            tools: options?.tools,
            maxToolCalls: (options?.maxToolCalls ?? 5) - 1,
            autoExecute: options?.autoExecute ?? true,
            temperature: options?.temperature,
            maxTokens: options?.maxTokens,
            systemPrompt: options?.systemPrompt,
            replaceSystemPrompt: options?.replaceSystemPrompt ?? false,
            keepToolsAvailable: options?.keepToolsAvailable ?? false
        )

        return try await generateWithTools(continuedPrompt, options: continuationOptions)
    }

    // MARK: - Private Helpers

    /// Generate text using streaming and collect all tokens into a single string.
    private static func generateAndCollect(
        _ prompt: String,
        temperature: Float?,
        maxTokens: Int?
    ) async throws -> String {
        let genOptions = LLMGenerationOptions(
            maxTokens: maxTokens ?? 1024,
            temperature: temperature ?? 0.3  // Lower temperature for consistent tool calling
        )

        let streamResult = try await generateStream(prompt, options: genOptions)

        var responseText = ""
        for try await token in streamResult.stream {
            responseText += token
        }

        return responseText
    }
}
