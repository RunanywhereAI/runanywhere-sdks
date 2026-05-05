/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android implementation for tool calling (function calling) with LLMs.
 * Allows LLMs to request external actions (API calls, device functions, etc.)
 *
 * Wave E / KOT-08: All orchestration — generate, parse, validate, execute loop,
 * follow-up prompt construction — lives in commons via
 * rac_tool_calling_session_{create,step_with_result,destroy}_proto. Kotlin
 * keeps only the tool registry + a platform executor callback pipe.
 *
 * Mirrors Swift SDK's RunAnywhere+ToolCalling.swift public surface.
 */

package com.runanywhere.sdk.public.extensions.LLM

import ai.runanywhere.proto.v1.SDKError
import ai.runanywhere.proto.v1.ToolCallingSessionCreateRequest
import ai.runanywhere.proto.v1.ToolCallingSessionEvent
import ai.runanywhere.proto.v1.ToolCallingSessionStepWithResultRequest
import com.runanywhere.sdk.foundation.SDKLogger
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
 * Tool calling implementation behind the public RunAnywhere extension surface.
 * Kotlin side is a thin wrapper over the native session orchestration.
 */
internal object RunAnywhereToolCalling {
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
     */
    suspend fun executeTool(toolCall: ToolCall): ToolResult {
        val tool = ToolRegistry.get(toolCall.name)
        val callId = toolCall.call_id ?: toolCall.id
        val startedAtMs = System.currentTimeMillis()
        if (tool == null) {
            return ToolResult(
                tool_call_id = callId,
                name = toolCall.name,
                error = "Unknown tool: ${toolCall.name}",
                success = false,
                call_id = callId,
                started_at_ms = startedAtMs,
                completed_at_ms = System.currentTimeMillis(),
            )
        }
        return try {
            val result = tool.executor(toolCall)
            result.copy(
                tool_call_id = result.tool_call_id.ifBlank { callId },
                name = result.name.ifBlank { toolCall.name },
                success = result.error.isNullOrBlank(),
                call_id = result.call_id ?: callId,
                started_at_ms = result.started_at_ms.takeIf { it > 0 } ?: startedAtMs,
                completed_at_ms = result.completed_at_ms.takeIf { it > 0 } ?: System.currentTimeMillis(),
            )
        } catch (e: Exception) {
            logger.error("Tool execution failed: ${e.message}")
            ToolResult(
                tool_call_id = callId,
                name = toolCall.name,
                error = e.message ?: "Unknown error",
                success = false,
                call_id = callId,
                started_at_ms = startedAtMs,
                completed_at_ms = System.currentTimeMillis(),
            )
        }
    }

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
            val result = tool.executor(toolCall)
            val resultJson = result.result_json.ifBlank { "{}" }
            val error = result.error
            if (!error.isNullOrBlank()) {
                ToolCallingSessionStepWithResultRequest(
                    session_handle = sessionHandle,
                    tool_call_id = toolCallId,
                    error = error,
                )
            } else {
                ToolCallingSessionStepWithResultRequest(
                    session_handle = sessionHandle,
                    tool_call_id = toolCallId,
                    result_json = resultJson,
                )
            }
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
