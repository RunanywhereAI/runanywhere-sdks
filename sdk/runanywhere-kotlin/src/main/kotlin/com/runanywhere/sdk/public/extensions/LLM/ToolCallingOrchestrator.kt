/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android tool-calling orchestrator: owns the platform-side tool registry
 * and bridges executor callbacks through the native session ABI.
 *
 * All orchestration — generate, parse, validate, execute loop,
 * follow-up prompt construction — lives in commons via the single-call
 * run-loop ABI `rac_tool_calling_run_loop_proto`. Kotlin
 * keeps only the tool registry + a synchronous executor callback, and fans
 * coroutine cancellation into `rac_tool_calling_run_loop_cancel_proto`.
 *
 * Mirrors Swift's RunAnywhere+ToolCalling.swift `generateWithToolsCancellable`
 * exactly: the required callback publishes the cancel handle the moment it is
 * minted so a cancel coroutine on another thread can interrupt the in-flight
 * loop. The `actual` extension surface lives in
 * RunAnywhereToolCalling.jvmAndroid.kt and delegates here.
 */

package com.runanywhere.sdk.public.extensions.LLM

import ai.runanywhere.proto.v1.ToolCallingSessionCreateRequest
import com.runanywhere.sdk.foundation.bridge.extensions.defaults
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.NativeRunLoopHandleListener
import com.runanywhere.sdk.native.bridge.NativeToolExecuteListener
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicBoolean
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
 * Race-safe bridge from coroutine cancellation to the native run-loop handle.
 *
 * Cancellation can win the race with native handle publication. Remembering
 * both halves means exactly one cancel reaches native as soon as both are
 * available, regardless of their ordering.
 */
internal class RunLoopCancellationController(
    private val cancelRunLoop: (Long) -> Unit,
) {
    private val runLoopHandle = AtomicLong(0L)
    private val cancellationRequested = AtomicBoolean(false)
    private val cancellationDispatched = AtomicBoolean(false)

    fun publishHandle(handle: Long) {
        if (handle == 0L) return
        runLoopHandle.compareAndSet(0L, handle)
        dispatchIfReady()
    }

    fun requestCancellation() {
        cancellationRequested.set(true)
        dispatchIfReady()
    }

    private fun dispatchIfReady() {
        val handle = runLoopHandle.get()
        if (
            handle != 0L &&
            cancellationRequested.get() &&
            cancellationDispatched.compareAndSet(false, true)
        ) {
            cancelRunLoop(handle)
        }
    }
}

/**
 * Starts suspended, then runs its finalizer on the owner's Active ->
 * Cancelling transition. Unlike [Job.join], this does not wait for a blocking
 * JNI sibling to finish before forwarding cancellation to native.
 */
internal fun CoroutineScope.launchRunLoopCancellationWatcher(
    ownerJob: Job,
    controller: RunLoopCancellationController,
): Job =
    launch(start = CoroutineStart.UNDISPATCHED) {
        try {
            awaitCancellation()
        } finally {
            if (ownerJob.isCancelled) {
                controller.requestCancellation()
            }
        }
    }

/**
 * The native executor ABI is synchronous, so its calling thread must wait for
 * a suspend [ToolExecutor]. Supplying [ownerJob] makes that wait a structured
 * child of the generation instead of a detached `runBlocking` coroutine.
 */
internal fun <T> runBlockingToolExecutor(
    ownerJob: Job,
    block: suspend () -> T,
): T = runBlocking(ownerJob) { block() }

/** Pure request builder kept separate so zero-valued greedy sampling and
 * forced-tool routing cannot regress silently at the Kotlin/native boundary. */
internal fun makeToolCallingRunLoopRequest(
    prompt: String,
    options: ToolCallingOptions,
    llmOptions: RALLMGenerationOptions,
    tools: List<ToolDefinition>,
    validateCalls: Boolean?,
): ToolCallingSessionCreateRequest =
    ToolCallingSessionCreateRequest(
        prompt = prompt,
        max_tokens = options.max_tokens?.takeIf { it > 0 } ?: llmOptions.max_tokens,
        // Zero is a real greedy temperature. Do not use takeIf/non-zero
        // fallback here; the native tool loop now honors this value exactly.
        temperature = options.temperature ?: llmOptions.temperature,
        top_p = llmOptions.top_p,
        system_prompt =
            options.system_prompt?.takeIf { it.isNotEmpty() }
                ?: llmOptions.system_prompt?.takeIf { it.isNotEmpty() }
                ?: "",
        format =
            options.format
                ?: ai.runanywhere.proto.v1.ToolCallFormatName.TOOL_CALL_FORMAT_NAME_UNSPECIFIED,
        max_tool_calls = options.effectiveMaxToolCalls(),
        keep_tools_available = options.keep_tools_available,
        // Suppress thinking when either options surface asks for it (commons
        // prepends the no-think directive).
        disable_thinking = (options.disable_thinking ?: false) || llmOptions.disable_thinking,
        validate_calls = validateCalls,
        tools = tools,
        tool_choice =
            options.tool_choice.takeIf {
                it != ai.runanywhere.proto.v1.ToolChoiceMode.TOOL_CHOICE_MODE_UNSPECIFIED
            },
        forced_tool_name = options.forced_tool_name?.takeIf { it.isNotEmpty() },
        auto_execute = options.auto_execute,
        replace_system_prompt = options.replace_system_prompt,
        require_json_arguments = options.require_json_arguments,
    )

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
        } catch (e: CancellationException) {
            // Cancellation is control flow. Let the JNI callback bridge turn
            // it into a prompt return while the run-loop cancellation signal
            // aborts native generation.
            throw e
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

    private fun toolCallIdentifier(toolCall: ToolCall): String = toolCall.id

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
            started_at_ms = startedAtMs,
            completed_at_ms = completedAtMs,
        )

    // Generate with tools

    /**
     * Generates a response with tool calling support. The entire generate →
     * parse → validate → execute → loop cycle lives in commons via
     * `rac_tool_calling_run_loop_proto`; Kotlin only
     * supplies a synchronous tool executor and fans coroutine cancellation
     * into `rac_tool_calling_run_loop_cancel_proto`.
     *
     * Mirrors Swift's `generateWithToolsCancellable`: the required handle
     * callback publishes the cancel handle the moment it is minted, so the
     * cancel watcher running on another thread can interrupt the in-flight
     * native loop. The executor trampoline runs on the JNI thread that owns
     * the run loop and bridges the suspend [ToolExecutor] synchronously via a
     * parent-linked blocking bridge — the native loop blocks on it, exactly
     * like Swift's `NSCondition`-backed `ToolResultBox`, while coroutine
     * cancellation still reaches the executor.
     */
    suspend fun generateWithTools(
        prompt: String,
        options: ToolCallingOptions? = null,
        llmOptions: RALLMGenerationOptions? = null,
        validateCalls: Boolean? = null,
    ): ToolCallingResult =
        coroutineScope {
            require(RunAnywhere.isInitialized) { "SDK not initialized" }

            val opts = options ?: ToolCallingOptions()
            val llmOpts = llmOptions ?: RALLMGenerationOptions.defaults()
            val registeredTools = ToolRegistry.getAll()
            val tools = opts.tools.ifEmpty { registeredTools }
            val effectiveOpts = opts.copy(tools = tools)

            // Swift parity (`makeRunLoopRequest`): tool options override the
            // base LLM generation options field-by-field. Optional validation
            // remains unset when the caller does not provide it, preserving
            // commons' secure default (validate=true).
            val request =
                makeToolCallingRunLoopRequest(
                    prompt = prompt,
                    options = effectiveOpts,
                    llmOptions = llmOpts,
                    tools = tools,
                    validateCalls = validateCalls,
                )

            val parentJob = checkNotNull(currentCoroutineContext()[Job])
            val cancellationController =
                RunLoopCancellationController { handle ->
                    RunAnywhereBridge.racToolCallingRunLoopCancelProto(handle)
                }

            // The executor fires on the JNI thread that owns the run loop;
            // commons blocks on it until a ToolResult is returned. Bridge the
            // suspend executor synchronously. The JNI thread is dedicated to
            // this call, so blocking it is the intended contract (Swift parks
            // the C thread on an NSCondition here). Linking the bridge to the
            // generation Job ensures cancellation also unwinds a suspended
            // host executor instead of leaving detached work behind.
            val executor =
                NativeToolExecuteListener { toolCallBytes ->
                    val toolCall = ToolCall.ADAPTER.decode(toolCallBytes)
                    val startedAtMs = System.currentTimeMillis()
                    val result =
                        try {
                            runBlockingToolExecutor(parentJob) { executeTool(toolCall) }
                        } catch (_: CancellationException) {
                            makeToolResult(
                                name = toolCall.name,
                                success = false,
                                error = "Tool execution cancelled",
                                toolCallId = toolCallIdentifier(toolCall),
                                startedAtMs = startedAtMs,
                                completedAtMs = System.currentTimeMillis(),
                            )
                        }
                    ToolResult.ADAPTER.encode(result)
                }

            val onHandle =
                NativeRunLoopHandleListener { handle ->
                    cancellationController.publishHandle(handle)
                }

            // A child parked in awaitCancellation is finalized immediately
            // when this generation starts cancelling. This is deliberately
            // not a `parentJob.join()` watcher: join waits for completion and
            // therefore deadlocks the deadline behind a blocking JNI call.
            val cancelWatcher =
                launchRunLoopCancellationWatcher(parentJob, cancellationController)

            try {
                val resultBytes =
                    withContext(Dispatchers.IO) {
                        RunAnywhereBridge.racToolCallingRunLoopProto(
                            ToolCallingSessionCreateRequest.ADAPTER.encode(request),
                            executor,
                            onHandle,
                        )
                    }
                resultBytes?.let { ToolCallingResult.ADAPTER.decode(it) }
                    ?: ToolCallingResult(
                        text = "",
                        is_complete = false,
                        error_message = "racToolCallingRunLoopProto returned null",
                        error_code = -1,
                    )
            } finally {
                // On success this tears down the parked watcher without
                // dispatching native cancel. On cancellation the watcher has
                // already forwarded the signal; joining prevents it from
                // escaping the generation scope.
                withContext(NonCancellable) {
                    cancelWatcher.cancelAndJoin()
                }
            }
        }
}
