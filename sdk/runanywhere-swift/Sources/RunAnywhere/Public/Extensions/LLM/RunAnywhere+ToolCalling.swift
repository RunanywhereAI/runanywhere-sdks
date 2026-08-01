//
//  RunAnywhere+ToolCalling.swift
//  RunAnywhere SDK
//
//  Public API for tool calling (function calling) with LLMs.
//  Allows LLMs to request external actions (API calls, device functions, etc.)
//
//  ARCHITECTURE:
//  - C++ owns the orchestration loop (`rac_tool_calling_run_loop_proto`).
//    Swift only carries the tool registry (closures) and trampolines
//    a Swift `ToolExecutor` invocation through the C executor callback.
//  - All parsing, validation, prompt formatting, and follow-up generation
//    happens in commons. There is no Swift-side orchestration loop.
//
//  *** ALL TOOL-CALLING LOGIC IS IN C++ (rac_tool_calling.h) - NO SWIFT FALLBACKS ***
//

import CRACommons
import Foundation
import os.lock
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
    typealias HandlePublishedCallback = @convention(c) (
        UInt64,
        UnsafeMutableRawPointer?
    ) -> Void
    typealias RunLoop = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        ExecuteCallback,
        UnsafeMutableRawPointer?,
        HandlePublishedCallback,
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t
    typealias Cancel = @convention(c) (UInt64) -> rac_result_t

    static let runLoopName = "rac_tool_calling_run_loop_proto"
    static let cancelName = "rac_tool_calling_run_loop_cancel_proto"

    static let runLoop = NativeProtoABI.load(runLoopName, as: RunLoop.self)
    static let cancel = NativeProtoABI.load(cancelName, as: Cancel.self)
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
    /// await RunAnywhere.registerTool(
    ///     RAToolDefinition(
    ///         name: "get_weather",
    ///         description: "Gets current weather for a location",
    ///         parameters: [
    ///             RAToolParameter(name: "location", type: .string, description: "City name")
    ///         ]
    ///     )
    /// ) { args in
    ///     let location = args["location"]?.string ?? "Unknown"
    ///     // Call weather API...
    ///     return [
    ///         "temperature": RAToolValue(72),
    ///         "condition": RAToolValue("Sunny")
    ///     ]
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

        let parsedArgs: [String: RAToolValue]
        do {
            parsedArgs = try RAToolValue.parseObjectJSON(toolCall.argumentsJson)
        } catch {
            // Parse failure used to be swallowed into an empty dict, which made
            // bad-JSON inputs look like success with no arguments. Surface the
            // failure as success=false so callers can distinguish parse errors
            // from genuine empty-argument calls.
            return makeToolResult(
                name: toolName,
                success: false,
                error: "Failed to parse tool arguments: \(error.localizedDescription)",
                toolCallID: toolCallID
            )
        }

        do {
            let result = try await tool.executor(parsedArgs)
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
    /// loop to the C++ commons layer (`rac_tool_calling_run_loop_proto`).
    /// Swift only registers a `@convention(c)` trampoline so the C loop can
    /// reach the Swift `ToolExecutor` closures stored in `ToolRegistry`.
    ///
    /// - Parameters:
    ///   - prompt: The user's prompt
    ///   - options: Generated LLM generation options.
    ///   - toolOptions: Generated tool-calling options. If omitted, the
    ///                  `options.toolCalling` payload is used when present,
    ///                  otherwise SDK defaults are applied.
    ///   - toolChoice: Optional override that forces `toolOptions.toolChoice`.
    ///                 Mirrors the OpenAI `tool_choice` knob: callers can pin
    ///                 the LLM to NONE / AUTO / SPECIFIC without having to
    ///                 manually mutate a `RAToolCallingOptions` proto.
    ///   - forcedToolName: Companion to `toolChoice=SPECIFIC` — the tool name
    ///                     the LLM is forced to invoke. Overrides
    ///                     `toolOptions.forcedToolName` when non-nil.
    ///   - validateCalls: Optional override for the IDL-level
    ///                    `validate_calls` knob on
    ///                    `ToolCallingSessionCreateRequest`
    ///                    (idl/tool_calling.proto:404). When `nil` the field
    ///                    is left unset and commons applies its default
    ///                    (`true` — i.e. enforce schema + registry checks
    ///                    before invoking the executor). Hosts that delegate
    ///                    validation/authorization to the executor closure
    ///                    (dynamic tool registries, executor-side argument
    ///                    inspection) MUST pass `validateCalls: false` so the
    ///                    C++ loop forwards every parsed call to the executor
    ///                    without short-circuiting on registry / schema
    ///                    mismatches.
    ///   - history: Prior conversation turns as a flat alternating list
    ///              `[user0, asst0, user1, asst1, ...]`, EXCLUDING the current
    ///              turn (which travels as `prompt`). Threaded into commons so
    ///              the tool-calling loop keeps multi-turn context, matching the
    ///              standard path. Defaulted empty for source compatibility.
    /// - Returns: Generated `RAToolCallingResult` with final text, tool calls,
    ///            and any executed tool results.
    ///
    /// Note: `tool_choice` / `forced_tool_name` live on the
    /// `RAToolCallingOptions` proto (fields 13/14, idl/tool_calling.proto).
    /// They are applied here on the effective options so future commons
    /// support automatically picks them up; the
    /// session-create request itself has reserved-7-10 today, so end-to-end
    /// propagation to native parse/validate helpers is pending the commons
    /// builder that snapshots options from the request.
    static func generateWithTools(
        prompt: String,
        options: RALLMGenerationOptions = .defaults(),
        toolOptions: RAToolCallingOptions? = nil,
        toolChoice: RAToolChoiceMode? = nil,
        forcedToolName: String? = nil,
        validateCalls: Bool? = nil,
        // TC-2: when true, one model turn may request multiple tools; commons
        // executes the whole batch before one follow-up prompt instead of
        // one LLM round-trip per tool. Default false preserves the
        // historical single-call-per-turn behavior.
        parallelToolCalls: Bool? = nil,
        history: [String] = []
    ) async throws -> RAToolCallingResult {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()

        var tcOpts = toolOptions ?? (options.hasToolCalling ? options.toolCalling : RAToolCallingOptions.defaults())
        if let toolChoice {
            tcOpts.toolChoice = toolChoice
        }
        if let forcedToolName {
            tcOpts.forcedToolName = forcedToolName
        }
        if let parallelToolCalls {
            tcOpts.parallelToolCalls = parallelToolCalls
        }
        let registeredTools = await ToolRegistry.shared.getAll()
        let tools = tcOpts.tools.isEmpty ? registeredTools : tcOpts.tools

        let request = makeRunLoopRequest(
            prompt: prompt,
            options: options,
            toolOptions: tcOpts,
            tools: tools,
            validateCalls: validateCalls,
            history: history
        )
        let requestBytes = try request.serializedData()
        let runLoop = try NativeProtoABI.require(
            ToolCallingRunLoopProtoABI.runLoop,
            named: ToolCallingRunLoopProtoABI.runLoopName
        )
        let cancelFn = try NativeProtoABI.require(
            ToolCallingRunLoopProtoABI.cancel,
            named: ToolCallingRunLoopProtoABI.cancelName
        )
        return try await generateWithToolsCancellable(
            requestBytes: requestBytes,
            runLoop: runLoop,
            cancelFn: cancelFn
        )
    }

    /// Cancellation-aware variant. Commons publishes the native run-loop
    /// handle synchronously through `toolRunLoopHandlePublished`, before its
    /// first generation iteration. `HandleBox` coordinates that callback
    /// with Swift task cancellation and forwards cancellation through
    /// `rac_tool_calling_run_loop_cancel_proto`.
    private static func generateWithToolsCancellable(
        requestBytes: Data,
        runLoop: ToolCallingRunLoopProtoABI.RunLoop,
        cancelFn: ToolCallingRunLoopProtoABI.Cancel
    ) async throws -> RAToolCallingResult {
        let handleBox = HandleBox(cancel: cancelFn)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RAToolCallingResult, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let context = ToolExecuteContext()
                    let contextPtr = Unmanaged.passRetained(context).toOpaque()
                    let handleContextPtr = Unmanaged.passUnretained(handleBox).toOpaque()
                    var outBuffer = rac_proto_buffer_t()
                    let status = requestBytes.withUnsafeBytes { rawBuffer -> rac_result_t in
                        runLoop(
                            rawBuffer.bindMemory(to: UInt8.self).baseAddress,
                            rawBuffer.count,
                            toolExecuteTrampoline,
                            contextPtr,
                            toolRunLoopHandlePublished,
                            handleContextPtr,
                            &outBuffer
                        )
                    }
                    if Task.isCancelled { handleBox.requestCancellation() }
                    Unmanaged<ToolExecuteContext>.fromOpaque(contextPtr).release()
                    handleBox.clear()

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
        } onCancel: {
            handleBox.requestCancellation()
        }
    }

    // MARK: - Private Helpers

    private static func toolCallIdentifier(_ toolCall: RAToolCall) -> String? {
        toolCall.id.isEmpty ? nil : toolCall.id
    }

    private static func makeToolResult(
        name: String,
        success: Bool,
        result: [String: RAToolValue] = [:],
        error: String? = nil,
        toolCallID: String? = nil
    ) -> RAToolResult {
        // The typed `result` map was removed — `resultJson` is the
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
        }
        return toolResult
    }

    /// Build the `ToolCallingSessionCreateRequest` proto consumed by
    /// `rac_tool_calling_run_loop_proto`. Applies `toolOptions`
    /// overrides on top of the base LLM generation options and forwards the
    /// registered tool list.
    private static func makeRunLoopRequest(
        prompt: String,
        options: RALLMGenerationOptions,
        toolOptions: RAToolCallingOptions,
        tools: [RAToolDefinition],
        validateCalls: Bool? = nil,
        // Prior conversation turns as a flat alternating list
        // `[user0, asst0, ...]`, EXCLUDING the current turn (which is `prompt`).
        // commons threads these into every generate in the loop so multi-turn
        // tool use keeps context. Same contract as the standard path's
        // ChatMessage history, as strings.
        history: [String] = []
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
        request.format = toolOptions.format
        request.maxToolCalls = UInt32(toolOptions.maxToolCalls > 0 ? toolOptions.maxToolCalls : 5)
        request.autoExecute = toolOptions.autoExecute
        request.replaceSystemPrompt = toolOptions.replaceSystemPrompt
        request.requireJsonArguments = toolOptions.requireJsonArguments
        request.keepToolsAvailable = toolOptions.keepToolsAvailable
        // TC-2: mirrors ToolCallingOptions.parallelToolCalls onto the
        // session-create envelope (proto field 20) — the run-loop reads
        // parallel_tool_calls from THIS request, not from the inline
        // ToolCallingOptions snapshot.
        request.parallelToolCalls = toolOptions.parallelToolCalls
        // `validate_calls` is `optional bool` on the proto so
        // hosts that delegate validation/authorization to their executor (or
        // use dynamic tool registries where argument inspection happens
        // inside the executor) can opt out via `validateCalls: false`. When
        // the caller did not supply a value, leave the field unset so
        // commons applies its documented default (true).
        if let validateCalls {
            request.validateCalls = validateCalls
        }
        // Thread tool_choice / forced_tool_name
        // all the way through to the commons request envelope (fields 7/8 on
        // ToolCallingSessionCreateRequest) so the run-loop / session APIs see
        // them — not just the inline RAToolCallingOptions snapshot.
        if toolOptions.toolChoice != .unspecified {
            request.toolChoice = toolOptions.toolChoice
        }
        if toolOptions.hasForcedToolName, !toolOptions.forcedToolName.isEmpty {
            request.forcedToolName = toolOptions.forcedToolName
        }
        // Suppress thinking when either options surface asks for it.
        request.disableThinking = toolOptions.disableThinking || options.disableThinking
        // Prior conversation turns (flat alternating [user, asst, ...] of prior
        // turns, excluding the current turn) so the commons run-loop keeps
        // multi-turn context. `history` is a swift-protobuf repeated field
        // (proto field 19), assignable directly. Empty by default — a no-op
        // for single-turn callers.
        request.history = history
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
/// emitted by the C loop. Bridges async-to-sync via an `NSCondition`-backed
/// `ToolResultBox`: a detached Task runs the executor on the cooperative
/// pool, and the calling C thread parks on `NSCondition.wait(until:)` with
/// a generous timeout. Using `NSCondition` instead of `DispatchSemaphore`
/// keeps libdispatch's worker-thread budget free for the cooperative pool
/// to make progress under high concurrency (50× simultaneous tool calls in
/// the regression test): semaphore wait pins one
/// libdispatch worker per in-flight tool, while `NSCondition.wait` releases
/// the underlying mutex and parks the thread on a kernel wait queue with no
/// libdispatch entanglement. The timeout caps the worst case so a hung
/// executor surfaces as a failed `ToolResult` instead of an indefinite
/// thread-pool stall. Errors / unknown tools are returned as failed
/// `ToolResult`s so the C loop can record them and continue or terminate
/// per its policy.
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

    // Park on an `NSCondition`-backed result box while the detached Task
    // resolves the executor. The detached Task gets explicit
    // `.userInitiated` priority so the cooperative scheduler hoists it over
    // background work; the calling thread parks via `awaitResult(timeout:)`
    // with a generous cap so a misbehaving executor cannot wedge the C
    // loop indefinitely.
    let resultBox = ToolResultBox()
    Task.detached(priority: .userInitiated) {
        let result = await RunAnywhere.executeTool(toolCall)
        resultBox.set(result)
    }
    let toolResult = resultBox.awaitResult(timeout: 120.0) ?? failedResult(
        name: toolCall.name,
        error: "Tool executor timed out or returned no result"
    )

    return writeToolResult(toolResult: toolResult, into: outBuffer, logger: logger)
}

/// Single-slot box used to ferry an async-produced `RAToolResult` back to the
/// blocking C trampoline. `NSCondition` provides both mutual exclusion and
/// thread parking; the calling C thread waits on the condition while the
/// detached executor Task delivers the result. This avoids
/// `DispatchSemaphore`'s tendency to occupy a libdispatch worker thread for
/// the duration of the wait, which under heavy concurrent tool-call load
/// could starve the libdispatch pool the
/// cooperative scheduler also draws from.
private final class ToolResultBox: @unchecked Sendable {
    private let condition = NSCondition()
    private var stored: RAToolResult?

    func set(_ value: RAToolResult) {
        condition.lock()
        stored = value
        condition.signal()
        condition.unlock()
    }

    /// Park the calling thread on the condition until a result is set or the
    /// deadline elapses. Returns `nil` if the timeout fires before the
    /// detached executor delivered a result.
    func awaitResult(timeout: TimeInterval) -> RAToolResult? {
        let deadline = Date(timeIntervalSinceNow: timeout)
        condition.lock()
        defer { condition.unlock() }
        while stored == nil {
            if !condition.wait(until: deadline) {
                return nil
            }
        }
        return stored
    }
}

private let toolRunLoopHandlePublished: ToolCallingRunLoopProtoABI.HandlePublishedCallback = { handle, userData in
    guard let userData else { return }
    let handleBox = Unmanaged<HandleBox>.fromOpaque(userData).takeUnretainedValue()
    handleBox.publish(handle)
}

/// Thread-safe bridge between the native handle-publication callback and the
/// Swift task cancellation handler. A cancellation requested before handle
/// publication is delivered asynchronously immediately after publication so
/// the callback does not re-enter the tool-calling C ABI.
private final class HandleBox: @unchecked Sendable {
    private struct State {
        var handle: UInt64 = 0
        var cancellationRequested = false
        var cancellationDelivered = false
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: State())
    private let cancel: ToolCallingRunLoopProtoABI.Cancel

    init(cancel: @escaping ToolCallingRunLoopProtoABI.Cancel) {
        self.cancel = cancel
    }

    func publish(_ handle: UInt64) {
        let shouldCancel = state.withLock { state in
            state.handle = handle
            guard state.cancellationRequested, !state.cancellationDelivered else { return false }
            state.cancellationDelivered = true
            return true
        }
        guard shouldCancel else { return }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            _ = cancel(handle)
        }
    }

    func requestCancellation() {
        let handle = state.withLock { state -> UInt64 in
            state.cancellationRequested = true
            guard state.handle != 0, !state.cancellationDelivered else { return 0 }
            state.cancellationDelivered = true
            return state.handle
        }
        if handle != 0 {
            _ = cancel(handle)
        }
    }

    func clear() {
        state.withLock { $0.handle = 0 }
    }
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
