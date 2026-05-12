/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android tool-calling orchestrator: owns the platform-side tool registry
 * and bridges executor callbacks through the native session ABI.
 *
 * Wave E / KOT-08: All orchestration — generate, parse, validate, execute loop,
 * follow-up prompt construction — lives in commons via
 * rac_tool_calling_session_{create,step_with_result,destroy}_proto. Kotlin
 * keeps only the tool registry + a platform executor callback pipe.
 *
 * Mirrors the private `ToolRegistry` + native-bridge machinery in Swift's
 * RunAnywhere+ToolCalling.swift. The `actual` extension surface lives in
 * RunAnywhereToolCalling.jvmAndroid.kt and delegates here.
 */

package com.runanywhere.sdk.public.extensions.LLM

import ai.runanywhere.proto.v1.SDKError
import ai.runanywhere.proto.v1.ToolCallingSessionCreateRequest
import ai.runanywhere.proto.v1.ToolCallingSessionEvent
import ai.runanywhere.proto.v1.ToolCallingSessionStepWithResultRequest
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.NativeProtoProgressListener
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

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

    // ========================================================================
    // TOOL REGISTRATION
    // ========================================================================

    suspend fun registerTool(definition: ToolDefinition, executor: ToolExecutor) {
        ToolRegistry.register(definition, executor)
        logger.info("Registered tool: ${definition.name}")
    }

    suspend fun unregisterTool(toolName: String) {
        ToolRegistry.unregister(toolName)
        logger.info("Unregistered tool: $toolName")
    }

    suspend fun getRegisteredTools(): List<ToolDefinition> = ToolRegistry.getAll()

    suspend fun clearTools() {
        ToolRegistry.clear()
        logger.info("Cleared all registered tools")
    }

    // ========================================================================
    // TOOL EXECUTION
    // ========================================================================

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
    ): ToolResult = ToolResult(
        tool_call_id = toolCallId,
        name = name,
        result_json = RAToolValue.jsonString(from = result),
        error = error,
        success = success,
        call_id = toolCallId.takeIf { it.isNotEmpty() },
        started_at_ms = startedAtMs,
        completed_at_ms = completedAtMs,
    )

    // ========================================================================
    // GENERATE WITH TOOLS
    // ========================================================================

    /**
     * Generates a response with tool calling support. The entire generate →
     * parse → validate → execute → loop cycle lives in commons; Kotlin only
     * forwards tool executions and awaits the final result.
     */
    suspend fun generateWithTools(
        prompt: String,
        options: ToolCallingOptions? = null,
    ): ToolCallingResult {
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
                validate_calls = true,
                tools = tools,
            )

        val completion = CompletableDeferred<ToolCallingResult>()
        var sessionHandle = 0L

        val listener =
            NativeProtoProgressListener { bytes ->
                val event = ToolCallingSessionEvent.ADAPTER.decode(bytes)
                when {
                    event.final_result != null -> {
                        if (!completion.isCompleted) completion.complete(event.final_result)
                    }
                    event.tool_call != null -> {
                        // Execute the tool on a non-JNI thread; feed result
                        // back via step_with_result_proto. Run blocking on
                        // IO so the native callback thread stays unblocked
                        // only for the quick enqueue path.
                        val toolCall = event.tool_call
                        val handle = sessionHandle
                        runBlocking {
                            val tool = ToolRegistry.get(toolCall.name)
                            val stepRequest = buildStepRequest(handle, toolCall, tool)
                            val rc =
                                RunAnywhereBridge.racToolCallingSessionStepWithResultProto(
                                    ToolCallingSessionStepWithResultRequest.ADAPTER.encode(
                                        stepRequest,
                                    ),
                                )
                            if (rc != RunAnywhereBridge.RAC_SUCCESS &&
                                !completion.isCompleted
                            ) {
                                completion.complete(
                                    ToolCallingResult(
                                        text = "",
                                        is_complete = false,
                                        error_message =
                                            "racToolCallingSessionStepWithResultProto failed with rc=$rc",
                                        error_code = rc,
                                    ),
                                )
                            }
                        }
                    }
                    event.error_bytes != null -> {
                        val sdkError =
                            try {
                                SDKError.ADAPTER.decode(event.error_bytes.toByteArray())
                            } catch (_: Exception) {
                                null
                            }
                        if (!completion.isCompleted) {
                            completion.complete(
                                ToolCallingResult(
                                    text = "",
                                    is_complete = false,
                                    error_message = sdkError?.message ?: "Tool calling session error",
                                    error_code = sdkError?.c_abi_code ?: -1,
                                ),
                            )
                        }
                    }
                }
                true
            }

        sessionHandle =
            withContext(Dispatchers.IO) {
                RunAnywhereBridge.racToolCallingSessionCreateProto(
                    ToolCallingSessionCreateRequest.ADAPTER.encode(request),
                    listener,
                )
            }
        if (sessionHandle == 0L) {
            return ToolCallingResult(
                text = "",
                is_complete = false,
                error_message = "racToolCallingSessionCreateProto returned 0",
                error_code = -1,
            )
        }

        try {
            return completion.await()
        } finally {
            withContext(Dispatchers.IO) {
                RunAnywhereBridge.racToolCallingSessionDestroyProto(sessionHandle)
            }
        }
    }

    private suspend fun buildStepRequest(
        sessionHandle: Long,
        toolCall: ToolCall,
        tool: RegisteredTool?,
    ): ToolCallingSessionStepWithResultRequest {
        val toolCallId = toolCall.call_id ?: toolCall.id
        if (tool == null) {
            return ToolCallingSessionStepWithResultRequest(
                session_handle = sessionHandle,
                tool_call_id = toolCallId,
                error = "Unknown tool: ${toolCall.name}",
            )
        }
        return try {
            val args = RAToolValue.parseObjectJSON(toolCall.arguments_json)
            val resultMap = tool.executor(args)
            ToolCallingSessionStepWithResultRequest(
                session_handle = sessionHandle,
                tool_call_id = toolCallId,
                result_json = RAToolValue.jsonString(from = resultMap),
            )
        } catch (e: Exception) {
            logger.error("Tool execution failed: ${e.message}")
            ToolCallingSessionStepWithResultRequest(
                session_handle = sessionHandle,
                tool_call_id = toolCallId,
                error = e.message ?: "Unknown error",
            )
        }
    }
}
