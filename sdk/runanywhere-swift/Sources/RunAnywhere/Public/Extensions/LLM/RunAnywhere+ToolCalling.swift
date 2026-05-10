//
//  RunAnywhere+ToolCalling.swift
//  RunAnywhere SDK
//
//  Public API for tool calling (function calling) with LLMs.
//  Allows LLMs to request external actions (API calls, device functions, etc.)
//
//  ARCHITECTURE:
//  - C++ owns the orchestration loop (`rac_tool_calling_run_loop_proto`,
//    P2-T8). Swift only carries the tool registry (closures) and trampolines
//    a Swift `ToolExecutor` invocation through the C executor callback.
//  - All parsing, validation, prompt formatting, and follow-up generation
//    happens in commons. There is no Swift-side orchestration loop.
//
//  *** ALL TOOL-CALLING LOGIC IS IN C++ (rac_tool_calling.h) - NO SWIFT FALLBACKS ***
//

import CRACommons
import Darwin
import Foundation
import SwiftProtobuf

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

// MARK: - Native run-loop ABI binding

private enum ToolCallingRunLoopProtoABI {
    typealias ExecuteCallback = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<rac_proto_buffer_t>?,
        UnsafeMutableRawPointer?
    ) -> rac_result_t
    typealias RunLoop = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        ExecuteCallback?,
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t

    static let runLoopName = "rac_tool_calling_run_loop_proto"
    static let runLoop = NativeProtoABI.load(runLoopName, as: RunLoop.self)
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
            let result = try await tool.executor(RAToolValue.parseObjectJSON(toolCall.argumentsJson))
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
    /// Delegates the entire generate -> parse -> validate -> execute -> follow-up
    /// loop to the C++ commons layer (`rac_tool_calling_run_loop_proto`, P2-T8).
    /// Swift only registers a `@convention(c)` trampoline so the C loop can
    /// reach the Swift `ToolExecutor` closures stored in `ToolRegistry`.
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
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()

        let tcOpts = toolOptions ?? (options.hasToolCalling ? options.toolCalling : RAToolCallingOptions.defaults())
        let registeredTools = await ToolRegistry.shared.getAll()
        let tools = tcOpts.tools.isEmpty ? registeredTools : tcOpts.tools

        let request = makeRunLoopRequest(
            prompt: prompt,
            options: options,
            toolOptions: tcOpts,
            tools: tools
        )
        let requestBytes = try request.serializedData()
        let runLoop = try NativeProtoABI.require(
            ToolCallingRunLoopProtoABI.runLoop,
            named: ToolCallingRunLoopProtoABI.runLoopName
        )

        // Drain the run loop on a background thread so the synchronous C call
        // doesn't block the structured-concurrency thread pool.
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let context = ToolExecuteContext()
                let contextPtr = Unmanaged.passRetained(context).toOpaque()
                var outBuffer = rac_proto_buffer_t()
                let status = requestBytes.withUnsafeBytes { rawBuffer -> rac_result_t in
                    runLoop(
                        rawBuffer.bindMemory(to: UInt8.self).baseAddress,
                        rawBuffer.count,
                        toolExecuteTrampoline,
                        contextPtr,
                        &outBuffer
                    )
                }
                Unmanaged<ToolExecuteContext>.fromOpaque(contextPtr).release()

                defer { NativeProtoABI.free(&outBuffer) }
                guard status == RAC_SUCCESS else {
                    let message = outBuffer.error_message.map { String(cString: $0) }
                        ?? "Tool calling run loop failed: \(status)"
                    continuation.resume(throwing: SDKException(
                        code: .processingFailed,
                        message: message,
                        category: .component
                    ))
                    return
                }
                do {
                    let result = try NativeProtoABI.decode(
                        RAToolCallingResult.self,
                        from: outBuffer
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
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
        // IDL-13: the typed `result` map was removed — `resultJson` is the
        // canonical wire shape (the C++ tool-prompt formatter reads it
        // directly when building follow-up LLM prompts).
        var toolResult = RAToolResult()
        toolResult.name = name
        toolResult.success = success
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

    /// Build the `ToolCallingSessionCreateRequest` proto consumed by
    /// `rac_tool_calling_run_loop_proto`. Mirrors the loop's old Swift
    /// orchestration: applies `toolOptions` overrides on top of the base LLM
    /// generation options and forwards the registered tool list.
    private static func makeRunLoopRequest(
        prompt: String,
        options: RALLMGenerationOptions,
        toolOptions: RAToolCallingOptions,
        tools: [RAToolDefinition]
    ) -> RAToolCallingSessionCreateRequest {
        var request = RAToolCallingSessionCreateRequest()
        request.prompt = prompt

        let maxTokens: Int32
        if toolOptions.hasMaxTokens, toolOptions.maxTokens > 0 {
            maxTokens = toolOptions.maxTokens
        } else {
            maxTokens = options.maxTokens
        }
        request.maxTokens = maxTokens

        let temperature: Float
        if toolOptions.hasTemperature {
            temperature = toolOptions.temperature
        } else {
            temperature = options.temperature
        }
        request.temperature = temperature
        request.topP = options.topP

        if toolOptions.hasSystemPrompt, !toolOptions.systemPrompt.isEmpty {
            request.systemPrompt = toolOptions.systemPrompt
        } else if options.hasSystemPrompt, !options.systemPrompt.isEmpty {
            request.systemPrompt = options.systemPrompt
        }

        request.tools = tools
        request.formatHint = toolOptions.resolvedFormatName
        request.maxIterations = UInt32(max(toolOptions.maxToolCallCount, 0))
        request.keepToolsAvailable = toolOptions.keepToolsAvailable
        request.validateCalls = true
        return request
    }
}

// MARK: - C trampoline + context

/// Context passed through the C `user_data` pointer so the trampoline can
/// reach the Swift tool registry without capturing state in the
/// `@convention(c)` closure (Swift forbids generic captures there).
private final class ToolExecuteContext: @unchecked Sendable {
    let logger = SDKLogger(category: "RunAnywhere.ToolCalling.RunLoop")
}

/// Synchronously invoke the registered Swift `ToolExecutor` for a tool call
/// emitted by the C loop. Bridges async to sync via `DispatchSemaphore`,
/// matching the canonical Swift bridge pattern used elsewhere
/// (e.g. `CppBridge+Device.swift` HTTP callbacks). Errors / unknown tools are
/// surfaced as a failed `ToolResult` so the C loop can record them and
/// continue or terminate per its policy.
private let toolExecuteTrampoline: ToolCallingRunLoopProtoABI.ExecuteCallback = { inBytes, inSize, outBuffer, userData in
    guard let outBuffer else {
        return RAC_ERROR_NULL_POINTER
    }
    rac_proto_buffer_init(outBuffer)

    let context: ToolExecuteContext? = userData.map {
        Unmanaged<ToolExecuteContext>.fromOpaque($0).takeUnretainedValue()
    }
    let logger = context?.logger ?? SDKLogger(category: "RunAnywhere.ToolCalling.RunLoop")

    // Decode the incoming ToolCall.
    let toolCall: RAToolCall
    do {
        guard let inBytes, inSize > 0 else {
            let failed = failedResult(name: "", error: "Empty tool-call payload")
            return writeToolResult(toolResult: failed, into: outBuffer, logger: logger)
        }
        toolCall = try RAToolCall(serializedBytes: Data(bytes: inBytes, count: inSize))
    } catch {
        let failed = failedResult(
            name: "",
            error: "Failed to decode ToolCall: \(error.localizedDescription)"
        )
        return writeToolResult(toolResult: failed, into: outBuffer, logger: logger)
    }

    // Bridge the async Swift executor to the synchronous C callback.
    let semaphore = DispatchSemaphore(value: 0)
    let resultBox = ToolResultBox()
    Task.detached {
        let result = await RunAnywhere.executeTool(toolCall)
        resultBox.set(result)
        semaphore.signal()
    }
    semaphore.wait()
    let toolResult = resultBox.value ?? failedResult(
        name: toolCall.name,
        error: "Tool executor returned no result"
    )

    return writeToolResult(toolResult: toolResult, into: outBuffer, logger: logger)
}

/// Single-slot box used to ferry an async-produced `RAToolResult` back to the
/// blocking C trampoline. The semaphore enforces happens-before, but a
/// concurrency-safe wrapper keeps Swift 6 strict-concurrency happy.
private final class ToolResultBox: @unchecked Sendable {
    private var stored: RAToolResult?

    func set(_ value: RAToolResult) {
        stored = value
    }

    var value: RAToolResult? { stored }
}

private func failedResult(name: String, error: String) -> RAToolResult {
    var result = RAToolResult()
    result.name = name
    result.success = false
    result.resultJson = "{}"
    result.error = error
    return result
}

private func writeToolResult(
    toolResult: RAToolResult,
    into outBuffer: UnsafeMutablePointer<rac_proto_buffer_t>,
    logger: SDKLogger
) -> rac_result_t {
    do {
        let bytes = try toolResult.serializedData()
        let rc = bytes.withUnsafeBytes { raw -> rac_result_t in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
                return rac_proto_buffer_copy(nil, 0, outBuffer)
            }
            return rac_proto_buffer_copy(base, raw.count, outBuffer)
        }
        if rc != RAC_SUCCESS {
            logger.warning("rac_proto_buffer_copy failed: \(rc)")
        }
        return rc
    } catch {
        logger.warning("Failed to serialize ToolResult: \(error.localizedDescription)")
        let message = "Failed to serialize ToolResult: \(error.localizedDescription)"
        _ = message.withCString { cstr in
            rac_proto_buffer_set_error(outBuffer, RAC_ERROR_INTERNAL, cstr)
        }
        return RAC_ERROR_INTERNAL
    }
}
