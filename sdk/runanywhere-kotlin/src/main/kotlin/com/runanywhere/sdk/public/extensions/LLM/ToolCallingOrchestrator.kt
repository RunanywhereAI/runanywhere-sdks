/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android tool-calling orchestrator: owns the platform-side tool registry
 * and bridges executor callbacks through the native session ABI.
 *
 * All orchestration — generate, parse, validate, execute loop,
 * follow-up prompt construction — lives in commons via the single-call
 * run-loop ABI `rac_tool_calling_run_loop_with_handle_and_cb_proto`. Kotlin
 * keeps only the tool registry + a synchronous executor callback, and fans
 * coroutine cancellation into `rac_tool_calling_run_loop_cancel_proto`.
 *
 * Mirrors Swift's RunAnywhere+ToolCalling.swift `generateWithToolsCancellable`
 * exactly (the with-handle-and-cb variant publishes the cancel handle the
 * moment it is minted so a cancel coroutine on another thread can interrupt
 * the in-flight loop). The `actual` extension surface lives in
 * RunAnywhereToolCalling.jvmAndroid.kt and delegates here.
 */

package com.runanywhere.sdk.public.extensions.LLM

import ai.runanywhere.proto.v1.ToolCallingSessionCreateRequest
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.NativeRunLoopHandleListener
import com.runanywhere.sdk.native.bridge.NativeToolExecuteListener
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicLong

/**
 * Thread-safe tool registry for tool registration and lookup.
 */
private object ToolRegistry {
    private val mutex = Mutex()
    private val tools = mutableMapOf<String, RegisteredTool>()

    suspend fun register(definition: ToolDefinition, executor: ToolExecutor) =
        mutex.withLock {
            tools[definition.name] = RegisteredTool(definition, executor)
        }

    suspend fun unregister(toolName: String) =
        mutex.withLock {
            tools.remove(toolName)
        }

    suspend fun getAll(): List<ToolDefinition> =
        mutex.withLock {
            tools.values.map { it.definition }
        }

    suspend fun get(toolName: String): RegisteredTool? =
        mutex.withLock {
            tools[toolName]
        }

    suspend fun clear() =
        mutex.withLock {
            tools.clear()
        }
}

/**
 * Tool calling orchestrator behind the public `RunAnywhere.{registerTool,
 * unregisterTool, getRegisteredTools, clearTools, executeTool,
 * generateWithTools}` extension surface. Kotlin side is a thin wrapper over
 * the native session orchestration.
 */
internal object ToolCallingOrchestrator {
    private const val TAG = "ToolCalling"
    private val logger = SDKLogger(TAG)

    // Tool registration

    suspend fun registerTool(definition: ToolDefinition, executor: ToolExecutor) {
        ToolRegistry.register(definition, executor)
        logger.debug("Registered tool: ${definition.name}")
    }

    suspend fun unregisterTool(toolName: String) {
        ToolRegistry.unregister(toolName)
        logger.debug("Unregistered tool: $toolName")
    }

    suspend fun getRegisteredTools(): List<ToolDefinition> = ToolRegistry.getAll()

    suspend fun clearTools() {
        ToolRegistry.clear()
        logger.debug("Cleared all registered tools")
    }

    // Tool execution

    /**
     * Execute a tool call through its registered executor. Used by the
     * public `executeTool` API for callers that handle tool calls manually
     * outside the native session loop.
     *
     * Mirrors Swift's `RunAnywhere.executeTool(_:)`:
     *  1. Parse `toolCall.arguments_json` into a typed `Map<String, RAToolValue>`.
     *  2. Invoke the registered `ToolExecutor` to get a result map.
     *  3. Serialize the result map back to `result_json` on a `ToolResult` proto.
     */
    suspend fun executeTool(toolCall: ToolCall): ToolResult {
        val tool = ToolRegistry.get(toolCall.name)
        val callId = toolCallIdentifier(toolCall)
        val startedAtMs = System.currentTimeMillis()
        if (tool == null) {
            return makeToolResult(
                name = toolCall.name,
                success = false,
                error = "Unknown tool: ${toolCall.name}",
                toolCallId = callId,
                startedAtMs = startedAtMs,
                completedAtMs = System.currentTimeMillis(),
            )
        }
        return try {
            val args = RAToolValue.parseObjectJSON(toolCall.arguments_json)
            val resultMap = tool.executor(args)
            makeToolResult(
                name = toolCall.name,
                success = true,
                result = resultMap,
                toolCallId = callId,
                startedAtMs = startedAtMs,
                completedAtMs = System.currentTimeMillis(),
            )
        } catch (e: Exception) {
            logger.error("Tool execution failed: ${e.message}")
            makeToolResult(
                name = toolCall.name,
                success = false,
                error = e.message ?: "Unknown error",
                toolCallId = callId,
                startedAtMs = startedAtMs,
                completedAtMs = System.currentTimeMillis(),
            )
        }
    }

    /**
     * Mirrors Swift's `toolCallIdentifier(_:)` helper: prefer `id`, fall back
     * to `call_id`, otherwise an empty string.
     */
    private fun toolCallIdentifier(toolCall: ToolCall): String =
        toolCall.id.ifBlank { toolCall.call_id?.ifBlank { null } ?: "" }

    /**
     * Build a `ToolResult` proto from a typed result map. Mirrors Swift's
     * `makeToolResult(...)`: `result_json` is the canonical wire shape (the
     * C++ tool-prompt formatter reads it directly).
     */
    private fun makeToolResult(
        name: String,
        success: Boolean,
        result: Map<String, RAToolValue> = emptyMap(),
        error: String? = null,
        toolCallId: String,
        startedAtMs: Long,
        completedAtMs: Long,
    ): ToolResult =
        ToolResult(
            tool_call_id = toolCallId,
            name = name,
            result_json = RAToolValue.jsonString(from = result),
            error = error,
            success = success,
            call_id = toolCallId.takeIf { it.isNotEmpty() },
            started_at_ms = startedAtMs,
            completed_at_ms = completedAtMs,
        )

    // Generate with tools

    /**
     * Generates a response with tool calling support. The entire generate →
     * parse → validate → execute → loop cycle lives in commons via
     * `rac_tool_calling_run_loop_with_handle_and_cb_proto`; Kotlin only
     * supplies a synchronous tool executor and fans coroutine cancellation
     * into `rac_tool_calling_run_loop_cancel_proto`.
     *
     * Mirrors Swift's `generateWithToolsCancellable` (the with-handle-and-cb
     * variant publishes the cancel handle the moment it is minted, so the
     * cancel watcher running on another thread can interrupt the in-flight
     * native loop). The executor trampoline runs on the JNI thread that owns
     * the run loop and bridges the suspend [ToolExecutor] synchronously via
     * `runBlocking` — the native loop blocks on it, exactly like Swift's
     * `NSCondition`-backed `ToolResultBox`.
     */
    suspend fun generateWithTools(
        prompt: String,
        options: ToolCallingOptions? = null,
        validateCalls: Boolean? = null,
    ): ToolCallingResult =
        coroutineScope {
            require(RunAnywhere.isInitialized) { "SDK not initialized" }

            val opts = options ?: ToolCallingOptions()
            val registeredTools = ToolRegistry.getAll()
            val tools = opts.tools.ifEmpty { registeredTools }
            val effectiveOpts = opts.copy(tools = tools)

            val request =
                ToolCallingSessionCreateRequest(
                    prompt = prompt,
                    max_tokens = effectiveOpts.max_tokens ?: 0,
                    temperature = effectiveOpts.temperature ?: 0f,
                    top_p = 0f,
                    system_prompt = effectiveOpts.system_prompt ?: "",
                    format_hint = effectiveOpts.effectiveToolFormatHint(),
                    max_iterations = effectiveOpts.effectiveMaxIterations(),
                    keep_tools_available = effectiveOpts.keep_tools_available ?: false,
                    // Swift parity (`makeRunLoopRequest`):
                    // `validate_calls` is `optional bool` on the proto. When the
                    // caller did not supply a value leave it unset (null) so
                    // commons applies its documented default (true — enforce
                    // schema + registry checks). Hosts that delegate validation
                    // to their executor pass `validateCalls = false`.
                    validate_calls = validateCalls,
                    tools = tools,
                    // Thread the OpenAI-style
                    // tool_choice / forced_tool_name knobs all the way through to
                    // the canonical request envelope (idl/tool_calling.proto
                    // fields 7/8). Commons build_options_snapshot copies them onto
                    // the synthesized ToolCallingOptions before every
                    // format/validate proto call.
                    tool_choice =
                        effectiveOpts.tool_choice?.takeIf {
                            it != ai.runanywhere.proto.v1.ToolChoiceMode.TOOL_CHOICE_MODE_UNSPECIFIED
                        },
                    forced_tool_name = effectiveOpts.forced_tool_name?.takeIf { it.isNotEmpty() },
                )

            // Published synchronously by the native loop the moment the
            // cancellable handle is minted (before the first generate
            // iteration), so the cancel watcher below can fan a Job cancel
            // into the in-flight loop. Mirrors Swift's `HandleBox`. A plain
            // AtomicLong is sufficient: commons writes the handle on the JNI
            // thread before the loop runs and the cancel watcher only reads it.
            val runLoopHandle = AtomicLong(0L)

            // The executor fires on the JNI thread that owns the run loop;
            // commons blocks on it until a ToolResult is returned. Bridge the
            // suspend executor synchronously via runBlocking — the JNI thread
            // is dedicated to this call, so blocking it is the intended
            // contract (Swift parks the C thread on an NSCondition here).
            val executor =
                NativeToolExecuteListener { toolCallBytes ->
                    val toolCall = ToolCall.ADAPTER.decode(toolCallBytes)
                    val result = runBlocking { executeTool(toolCall) }
                    ToolResult.ADAPTER.encode(result)
                }

            val onHandle =
                NativeRunLoopHandleListener { handle ->
                    runLoopHandle.set(handle)
                }

            // Fan coroutine cancellation into the native loop
            // eagerly via a dedicated cancel-watcher on a NonCancellable
            // context. The watcher suspends on the parent Job's `join()` and
            // inspects the cancellation state once awoken — which happens on
            // the Active → Cancelling transition. Cancel is idempotent on the
            // native side, so racing this watcher with normal completion is
            // safe. Mirrors Swift's `withTaskCancellationHandler { } onCancel:`.
            val parentJob = currentCoroutineContext()[Job]
            val cancelWatcher =
                parentJob?.let { pj ->
                    CoroutineScope(Dispatchers.Default + NonCancellable).launch {
                        try {
                            pj.join()
                        } catch (_: CancellationException) {
                            // join() doesn't throw on cancel; defensive only.
                        }
                        val handle = runLoopHandle.get()
                        if (pj.isCancelled && handle != 0L) {
                            RunAnywhereBridge.racToolCallingRunLoopCancelProto(handle)
                        }
                    }
                }

            try {
                val resultBytes =
                    withContext(Dispatchers.IO) {
                        RunAnywhereBridge.racToolCallingRunLoopWithHandleAndCbProto(
                            ToolCallingSessionCreateRequest.ADAPTER.encode(request),
                            executor,
                            onHandle,
                        )
                    }
                resultBytes?.let { ToolCallingResult.ADAPTER.decode(it) }
                    ?: ToolCallingResult(
                        text = "",
                        is_complete = false,
                        error_message = "racToolCallingRunLoopWithHandleAndCbProto returned null",
                        error_code = -1,
                    )
            } finally {
                cancelWatcher?.cancel()
            }
        }
}
