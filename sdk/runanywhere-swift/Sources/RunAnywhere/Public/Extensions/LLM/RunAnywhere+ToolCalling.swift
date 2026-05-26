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
    typealias RunLoop = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        ExecuteCallback?,
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t
    // pass2-syn-007: with-handle variant publishes a cancel handle.
    typealias RunLoopWithHandle = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        ExecuteCallback?,
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<UInt64>?,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t
    typealias Cancel = @convention(c) (UInt64) -> rac_result_t

    static let runLoopName = "rac_tool_calling_run_loop_proto"
    static let runLoopWithHandleName = "rac_tool_calling_run_loop_with_handle_proto"
    static let cancelName = "rac_tool_calling_run_loop_cancel_proto"

    static let runLoop = NativeProtoABI.load(runLoopName, as: RunLoop.self)
    static let runLoopWithHandle =
        NativeProtoABI.load(runLoopWithHandleName, as: RunLoopWithHandle.self)
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
    /// - Returns: Generated `RAToolCallingResult` with final text, tool calls,
    ///            and any executed tool results.
    ///
    /// Note: `tool_choice` / `forced_tool_name` live on the
    /// `RAToolCallingOptions` proto (fields 13/14, idl/tool_calling.proto).
    /// They are applied here on the effective options so future commons
    /// support (pass2-syn-006 parent) automatically picks them up; the
    /// session-create request itself has reserved-7-10 today, so end-to-end
    /// propagation to native parse/validate helpers is pending the commons
    /// builder that snapshots options from the request.
    static func generateWithTools(
        prompt: String,
        options: RALLMGenerationOptions = .defaults(),
        toolOptions: RAToolCallingOptions? = nil,
        toolChoice: RAToolChoiceMode? = nil,
        forcedToolName: String? = nil,
        validateCalls: Bool? = nil
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
        let registeredTools = await ToolRegistry.shared.getAll()
        let tools = tcOpts.tools.isEmpty ? registeredTools : tcOpts.tools

        let request = makeRunLoopRequest(
            prompt: prompt,
            options: options,
            toolOptions: tcOpts,
            tools: tools,
            validateCalls: validateCalls
        )
        let requestBytes = try request.serializedData()
        // pass2-syn-007: prefer the with-handle variant so the surrounding
        // Task can cancel the in-flight native loop via
        // `withTaskCancellationHandler`. Falls back to the legacy ABI if the
        // newer entry point isn't exported by the loaded libcommons (e.g.
        // running against an older build of the static framework).
        let runLoopWithHandle = ToolCallingRunLoopProtoABI.runLoopWithHandle
        let cancelFn = ToolCallingRunLoopProtoABI.cancel
        if let runLoopWithHandle, let cancelFn {
            return try await generateWithToolsCancellable(
                requestBytes: requestBytes,
                runLoopWithHandle: runLoopWithHandle,
                cancelFn: cancelFn
            )
        }
        let runLoop = try NativeProtoABI.require(
            ToolCallingRunLoopProtoABI.runLoop,
            named: ToolCallingRunLoopProtoABI.runLoopName
        )

        // The legacy ABI has no cancel entry point, so the in-flight C call
        // itself runs to completion regardless of Task state. Even so, route
        // it through `withTaskCancellationHandler` + an upfront
        // `Task.checkCancellation()` so a Task cancelled before — or by the
        // time — the C call returns surfaces a `CancellationError` instead of
        // silently delivering the result. Matches the with-handle path's
        // Swift-level cancellation contract; only the in-flight cancel
        // remains a no-op until the with-handle ABI is exported.
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RAToolCallingResult, Error>) in
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
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
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
            // Best-effort: the legacy ABI cannot interrupt the in-flight
            // native loop. The post-call `Task.isCancelled` check in the
            // continuation body translates the Swift Task cancel into a
            // `CancellationError` once the C call returns.
        }
    }

    /// Cancellation-aware variant. Publishes the native run-loop handle via
    /// the with-handle ABI and wires `withTaskCancellationHandler` to fan a
    /// Swift Task cancel into `rac_tool_calling_run_loop_cancel_proto`.
    ///
    /// pass3-syn-059: the handle slot MUST be stable cross-thread storage
    /// that the C ABI writes to synchronously (commons writes
    /// `*out_run_loop_handle = handle` at
    /// `tool_calling_run_loop.cpp:391-393`, BEFORE any iteration work
    /// starts). `HandleBox` owns a heap-allocated `UInt64` cell whose
    /// address is passed directly into the C call — so the cancel handler
    /// observes the real handle the instant the native call publishes it,
    /// not after the entire synchronous loop returns. This mirrors the RN
    /// `onHandle: (handle: number) => void` synchronous-publish pattern
    /// from `RunAnywhere+ToolCalling.ts:247-252`.
    private static func generateWithToolsCancellable(
        requestBytes: Data,
        runLoopWithHandle: ToolCallingRunLoopProtoABI.RunLoopWithHandle,
        cancelFn: ToolCallingRunLoopProtoABI.Cancel
    ) async throws -> RAToolCallingResult {
        let handleBox = HandleBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RAToolCallingResult, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let context = ToolExecuteContext()
                    let contextPtr = Unmanaged.passRetained(context).toOpaque()
                    var outBuffer = rac_proto_buffer_t()
                    // Drive the C call through the HandleBox's heap cell so
                    // the handle written by commons is visible to onCancel
                    // mid-call, not just after the synchronous run loop
                    // returns.
                    let status = handleBox.withHandlePointer { handlePtr in
                        requestBytes.withUnsafeBytes { rawBuffer -> rac_result_t in
                            runLoopWithHandle(
                                rawBuffer.bindMemory(to: UInt8.self).baseAddress,
                                rawBuffer.count,
                                toolExecuteTrampoline,
                                contextPtr,
                                handlePtr,
                                &outBuffer
                            )
                        }
                    }
                    // Snapshot before clearing so the post-return cancel
                    // check (and any onCancel races against the same
                    // handleBox.clear) can still see the value the C call
                    // published.
                    let publishedHandle = handleBox.value
                    // If the Task was already cancelled by the time the
                    // native call returned, fan that into the loop's
                    // latched cancel slot — commons swallows cancels for
                    // already-completed handles, so this is a safe no-op
                    // when the loop finished cleanly.
                    if Task.isCancelled, publishedHandle != 0 {
                        _ = cancelFn(publishedHandle)
                    }
                    Unmanaged<ToolExecuteContext>.fromOpaque(contextPtr).release()
                    // Clear AFTER the post-call cancel fan-out so any
                    // onCancel firing concurrently with this teardown
                    // still observes the real handle.
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
            let activeHandle = handleBox.value
            if activeHandle != 0 {
                _ = cancelFn(activeHandle)
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
        tools: [RAToolDefinition],
        validateCalls: Bool? = nil
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
        // pass3-syn-149: `validate_calls` is `optional bool` on the proto so
        // hosts that delegate validation/authorization to their executor (or
        // use dynamic tool registries where argument inspection happens
        // inside the executor) can opt out via `validateCalls: false`. When
        // the caller did not supply a value, leave the field unset so
        // commons applies its documented default (true).
        if let validateCalls {
            request.validateCalls = validateCalls
        }
        // pass2-syn-006-followup-swift: thread tool_choice / forced_tool_name
        // all the way through to the commons request envelope (fields 7/8 on
        // ToolCallingSessionCreateRequest) so the run-loop / session APIs see
        // them — not just the inline RAToolCallingOptions snapshot.
        if toolOptions.toolChoice != .unspecified {
            request.toolChoice = toolOptions.toolChoice
        }
        if toolOptions.hasForcedToolName, !toolOptions.forcedToolName.isEmpty {
            request.forcedToolName = toolOptions.forcedToolName
        }
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
/// the regression test, swift-public-features-013): semaphore wait pins one
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
/// (swift-public-features-013) could starve the libdispatch pool the
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

/// pass2-syn-007 / pass3-syn-059: shared handle slot between the
/// DispatchQueue thread that owns the in-flight C call and the `onCancel`
/// closure that may fire from any thread.
///
/// The handle lives in a heap-allocated `UnsafeMutablePointer<UInt64>` cell
/// so its address is stable for the lifetime of the box and can be passed
/// directly to the C ABI. Commons writes `*out_run_loop_handle = handle`
/// synchronously inside `rac_tool_calling_run_loop_with_handle_proto`
/// before the iteration loop begins
/// (sdk/runanywhere-commons/src/features/llm/tool_calling_run_loop.cpp:391-393),
/// so `onCancel` reading `value` while the C call is in flight observes
/// the real handle — not zero. Reads/writes are coordinated through
/// OSAllocatedUnfairLock (the Swift 6 / iOS 16+ replacement for NSLock).
private final class HandleBox: @unchecked Sendable {
    // Stateless lock — the value lives in `cell` (a heap pointer) because
    // OSAllocatedUnfairLock's internal state has no stable address that
    // could be handed to the C ABI.
    private let lock = OSAllocatedUnfairLock<Void>(initialState: ())
    private let cell: UnsafeMutablePointer<UInt64>

    init() {
        cell = UnsafeMutablePointer<UInt64>.allocate(capacity: 1)
        cell.initialize(to: 0)
    }

    deinit {
        cell.deinitialize(count: 1)
        cell.deallocate()
    }

    /// Run `body` with the cell pointer so the C ABI can write the handle
    /// directly into shared storage. The lock is NOT held across `body`
    /// because the C call is synchronous on the caller's thread and the
    /// only concurrent reader (`value` from onCancel) takes the lock for
    /// its read; UnsafeMutablePointer load/store of UInt64 on supported
    /// platforms is naturally atomic for the read-after-write the cancel
    /// handler performs.
    func withHandlePointer<T>(_ body: (UnsafeMutablePointer<UInt64>) -> T) -> T {
        body(cell)
    }

    /// Current handle value. Safe to call from any thread.
    var value: UInt64 {
        lock.withLock { _ in cell.pointee }
    }

    /// Reset the handle to zero. Called after the C call returns so a
    /// late-firing `onCancel` no-ops instead of cancelling a stale handle.
    func clear() {
        lock.withLock { _ in cell.pointee = 0 }
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
