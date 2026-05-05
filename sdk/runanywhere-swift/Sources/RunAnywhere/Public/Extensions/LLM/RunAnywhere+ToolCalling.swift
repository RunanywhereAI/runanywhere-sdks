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

    func register(_ definition: RAToolDefinition, executor: @escaping ToolExecutor) {
        tools[definition.name] = RegisteredTool(definition: definition, executor: executor)
    }

    func unregister(_ toolName: String) {
        tools.removeValue(forKey: toolName)
    }

    func getAll() -> [RAToolDefinition] {
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
    ///     RAToolDefinition(
    ///         name: "get_weather",
    ///         description: "Gets current weather for a location",
    ///         parameters: [
    ///             RAToolParameter(name: "location", type: .string, description: "City name")
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
        _ definition: RAToolDefinition,
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
    static func getRegisteredTools() async -> [RAToolDefinition] {
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
    /// Returns a `RAToolResult` with success/failure status.
    ///
    /// - Parameter toolCall: The tool call to execute
    /// - Returns: Result of the tool execution
    static func executeTool(_ toolCall: RAToolCall) async -> RAToolResult {
        let toolName = toolCall.name
        let toolCallID = toolCallIdentifier(toolCall)

        guard let tool = await ToolRegistry.shared.get(toolName) else {
            return makeToolResult(
                name: toolName,
                success: false,
                error: "Unknown tool: \(toolName)",
                toolCallID: toolCallID
            )
        }

        do {
            let result = try await tool.executor(toolCall.arguments)
            return makeToolResult(
                name: toolName,
                success: true,
                result: result,
                toolCallID: toolCallID
            )
        } catch {
            return makeToolResult(
                name: toolName,
                success: false,
                error: error.localizedDescription,
                toolCallID: toolCallID
            )
        }
    }

    // MARK: - Generate with Tools

    /// Generates a response with tool calling support (CANONICAL_API §3).
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
    ///   - options: Generated LLM generation options.
    ///   - toolOptions: Generated tool-calling options. If omitted, the
    ///                  `options.toolCalling` payload is used when present,
    ///                  otherwise SDK defaults are applied.
    /// - Returns: Generated `RAToolCallingResult` with final text, tool calls,
    ///            and any executed tool results.
    static func generateWithTools(
        prompt: String,
        options: RALLMGenerationOptions = .defaults(),
        toolOptions: RAToolCallingOptions? = nil
    ) async throws -> RAToolCallingResult {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }
        try await ensureServicesReady()

        let tcOpts = toolOptions ?? (options.hasToolCalling ? options.toolCalling : RAToolCallingOptions.defaults())
        let registeredTools = await ToolRegistry.shared.getAll()
        let tools = tcOpts.tools.isEmpty ? registeredTools : tcOpts.tools

        var fullPrompt = prompt
        if !tools.isEmpty {
            fullPrompt = try CppBridge.ToolCalling.buildInitialPrompt(
                userPrompt: prompt,
                tools: tools,
                options: tcOpts
            )
        }

        var finalText = ""
        var toolCalls: [RAToolCall] = []
        var toolResults: [RAToolResult] = []
        var isComplete = true

        for _ in 0..<tcOpts.maxToolCallCount {
            let responseText = try await generateAndCollect(
                prompt: fullPrompt,
                baseOptions: options,
                toolOptions: tcOpts
            )

            // Parse using C++ implementation (SINGLE SOURCE OF TRUTH - NO FALLBACK)
            let (text, toolCall) = try CppBridge.ToolCalling.parseToolCall(
                from: responseText,
                options: tcOpts
            )
            finalText = text

            guard let toolCall = toolCall else {
                isComplete = true
                break
            }

            toolCalls.append(toolCall)

            guard tcOpts.autoExecute else {
                isComplete = false
                break
            }

            let validation = try CppBridge.ToolCalling.validateToolCall(
                toolCall,
                tools: tools,
                options: tcOpts
            )
            guard validation.isValid else {
                let error = validation.hasErrorMessage && !validation.errorMessage.isEmpty
                    ? validation.errorMessage
                    : validation.validationErrors.joined(separator: "; ")
                toolResults.append(makeToolResult(
                    name: toolCall.name,
                    success: false,
                    error: error.isEmpty ? "Tool call validation failed" : error,
                    toolCallID: toolCallIdentifier(toolCall)
                ))
                isComplete = false
                break
            }

            let executableToolCall = toolCallWithValidatedArguments(
                toolCall,
                validation: validation
            )
            let toolResult = await executeTool(executableToolCall)
            toolResults.append(toolResult)

            let followUpPrompt = try CppBridge.ToolCalling.buildFollowupPrompt(
                originalPrompt: prompt,
                tools: tools,
                toolResult: toolResult,
                options: tcOpts
            )
            fullPrompt = followUpPrompt.isEmpty ? prompt : followUpPrompt
            isComplete = false
        }

        var result = RAToolCallingResult()
        result.text = finalText
        result.toolCalls = toolCalls
        result.toolResults = toolResults
        result.isComplete = isComplete
        return result
    }

    // MARK: - Private Helpers

    private static func toolCallIdentifier(_ toolCall: RAToolCall) -> String? {
        if !toolCall.id.isEmpty {
            return toolCall.id
        }
        if !toolCall.callID.isEmpty {
            return toolCall.callID
        }
        return nil
    }

    private static func makeToolResult(
        name: String,
        success: Bool,
        result: [String: RAToolValue] = [:],
        error: String? = nil,
        toolCallID: String? = nil
    ) -> RAToolResult {
        var toolResult = RAToolResult()
        toolResult.name = name
        toolResult.success = success
        toolResult.result = result
        toolResult.resultJson = RAToolValue.jsonString(from: result)
        if let error {
            toolResult.error = error
        }
        if let toolCallID {
            toolResult.toolCallID = toolCallID
            toolResult.callID = toolCallID
        }
        return toolResult
    }

    private static func toolCallWithValidatedArguments(
        _ toolCall: RAToolCall,
        validation: RAToolCallValidationResult
    ) -> RAToolCall {
        guard !validation.normalizedArgumentsJson.isEmpty else {
            return toolCall
        }

        var normalized = toolCall
        normalized.argumentsJson = validation.normalizedArgumentsJson
        normalized.arguments = RAToolValue.parseObjectJSON(validation.normalizedArgumentsJson)
        return normalized
    }

    /// Generate text using streaming and collect all tokens into a single string.
    private static func generateAndCollect(
        prompt: String,
        baseOptions: RALLMGenerationOptions,
        toolOptions: RAToolCallingOptions
    ) async throws -> String {
        var genOptions = baseOptions
        if toolOptions.hasMaxTokens, toolOptions.maxTokens > 0 {
            genOptions.maxTokens = toolOptions.maxTokens
        }
        if toolOptions.hasTemperature {
            genOptions.temperature = toolOptions.temperature
        }
        genOptions.streamingEnabled = true
        var request = genOptions.toRALLMGenerateRequest(prompt: prompt)
        request.streamingEnabled = true

        let eventStream = try await generateStream(request)

        var responseText = ""
        for await event in eventStream {
            if !event.token.isEmpty {
                responseText += event.token
            }
            if event.isFinal {
                if !event.errorMessage.isEmpty {
                    throw SDKException.llm(.generationFailed, event.errorMessage)
                }
                break
            }
        }

        return responseText
    }
}
