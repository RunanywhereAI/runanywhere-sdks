/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android implementation for tool calling (function calling) with LLMs.
 * Allows LLMs to request external actions (API calls, device functions, etc.)
 *
 * ARCHITECTURE:
 * - CppBridgeToolCalling: C++ bridge for parsing <tool_call> tags (SINGLE SOURCE OF TRUTH)
 * - This file: Tool registration, executor storage, orchestration
 * - Orchestration: generate → parse (C++) → execute → loop
 *
 * *** ALL PARSING LOGIC IS IN C++ (rac_tool_calling.h) - NO KOTLIN FALLBACKS ***
 *
 * Mirrors Swift SDK's RunAnywhere+ToolCalling.swift
 */

package com.runanywhere.sdk.public.extensions.LLM

import ai.runanywhere.proto.v1.LLMGenerationOptions
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeToolCalling
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.generate
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

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
 */
internal object RunAnywhereToolCalling {
    private const val TAG = "ToolCalling"
    private val logger = SDKLogger(TAG)

    // ========================================================================
    // TOOL REGISTRATION
    // ========================================================================

    /**
     * Register a tool that the LLM can use.
     *
     * Tools are stored in-memory and available for all subsequent generateWithTools calls.
     * Executors run in Kotlin and have full access to Kotlin/Android APIs.
     *
     * @param definition Tool definition (name, description, parameters)
     * @param executor Suspend function that executes the tool
     */
    suspend fun registerTool(
        definition: ToolDefinition,
        executor: ToolExecutor,
    ) {
        ToolRegistry.register(definition, executor)
        logger.info("Registered tool: ${definition.name}")
    }

    /**
     * Unregister a tool by name.
     *
     * @param toolName The name of the tool to remove
     */
    suspend fun unregisterTool(toolName: String) {
        ToolRegistry.unregister(toolName)
        logger.info("Unregistered tool: $toolName")
    }

    /**
     * Get all registered tool definitions.
     *
     * @return List of registered tool definitions
     */
    suspend fun getRegisteredTools(): List<ToolDefinition> {
        return ToolRegistry.getAll()
    }

    /**
     * Clear all registered tools.
     */
    suspend fun clearTools() {
        ToolRegistry.clear()
        logger.info("Cleared all registered tools")
    }

    // ========================================================================
    // TOOL EXECUTION
    // ========================================================================

    /**
     * Execute a tool call.
     *
     * Looks up the tool in the registry and invokes its executor with the provided arguments.
     * Returns a ToolResult with success/failure status.
     *
     * @param toolCall The tool call to execute
     * @return Result of the tool execution
     */
    suspend fun executeTool(toolCall: ToolCall): ToolResult {
        val tool = ToolRegistry.get(toolCall.name)
        val startedAtMs = System.currentTimeMillis()
        val callId = toolCall.call_id ?: toolCall.id

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
                completed_at_ms =
                    result.completed_at_ms.takeIf { it > 0 }
                        ?: System.currentTimeMillis(),
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
     * Generates a response with tool calling support.
     *
     * Orchestrates a generate → parse → execute → loop cycle:
     * 1. Builds a system prompt describing available tools (C++)
     * 2. Generates LLM response
     * 3. Parses output for `<tool_call>` tags (C++ - SINGLE SOURCE OF TRUTH)
     * 4. If a tool call is found and auto_execute is true, executes and continues
     * 5. Repeats until no more tool calls or max_iterations is reached
     *
     * @param prompt The user's prompt
     * @param options Tool calling options
     * @return Result containing final text, all tool calls made, and their results
     */
    suspend fun generateWithTools(
        prompt: String,
        options: ToolCallingOptions? = null,
    ): ToolCallingResult {
        // Ensure SDK is initialized
        require(RunAnywhere.isInitialized) { "SDK not initialized" }

        val opts =
            options ?: ToolCallingOptions(
                max_iterations = 5,
                auto_execute = true,
                format_hint = "default",
            )
        val registeredTools = ToolRegistry.getAll()
        val tools = opts.tools.ifEmpty { registeredTools }
        val executionOptions = opts.copy(tools = tools)

        var fullPrompt =
            CppBridgeToolCalling.buildInitialPrompt(
                userPrompt = prompt,
                tools = tools,
                options = executionOptions,
            )

        val allToolCalls = mutableListOf<ToolCall>()
        val allToolResults = mutableListOf<ToolResult>()
        var finalText = ""

        val maxIterations = executionOptions.effectiveMaxIterations()
        repeat(maxIterations) { iteration ->
            logger.debug("Tool calling iteration $iteration")

            // Generate response
            val responseText =
                generateAndCollect(
                    fullPrompt,
                    executionOptions.temperature,
                    executionOptions.max_tokens,
                    executionOptions,
                )

            // Parse for tool calls using C++ (SINGLE SOURCE OF TRUTH - NO FALLBACK)
            val (cleanText, toolCall) =
                CppBridgeToolCalling.parseToolCallToObject(responseText, executionOptions)
            finalText = cleanText

            if (toolCall == null) {
                logger.debug("No tool call found, generation complete")
                return ToolCallingResult(
                    text = finalText,
                    tool_calls = allToolCalls,
                    tool_results = allToolResults,
                    is_complete = true,
                    iterations_used = iteration + 1,
                )
            }

            allToolCalls.add(toolCall)
            logger.info("Found tool call: ${toolCall.name}")

            if (!executionOptions.auto_execute) {
                return ToolCallingResult(
                    text = finalText,
                    tool_calls = allToolCalls,
                    tool_results = emptyList(),
                    is_complete = false,
                    iterations_used = iteration + 1,
                )
            }

            val validation =
                CppBridgeToolCalling.validateToolCall(
                    toolCall = toolCall,
                    tools = tools,
                    options = executionOptions,
                )
            if (!validation.is_valid) {
                val validationError =
                    validation.error_message
                        ?: validation.validation_errors
                            .joinToString("; ")
                            .ifBlank { "Tool call validation failed" }
                val failedResult =
                    ToolResult(
                        tool_call_id = toolCall.call_id ?: toolCall.id,
                        name = toolCall.name,
                        error = validationError,
                        success = false,
                        call_id = toolCall.call_id ?: toolCall.id,
                    )
                allToolResults.add(failedResult)
                return ToolCallingResult(
                    text = finalText,
                    tool_calls = allToolCalls,
                    tool_results = allToolResults,
                    is_complete = false,
                    iterations_used = iteration + 1,
                    error_message = validationError,
                    error_code = validation.error_code,
                )
            }

            // Execute tool
            val executableToolCall =
                if (validation.normalized_arguments_json.isNotBlank()) {
                    toolCall.copy(arguments_json = validation.normalized_arguments_json)
                } else {
                    toolCall
                }
            val result = executeTool(executableToolCall)
            allToolResults.add(result)
            val status = if (result.error.isNullOrBlank()) "success" else "failed"
            logger.info("Tool ${toolCall.name} executed: $status")

            // Build follow-up prompt using C++ (SINGLE SOURCE OF TRUTH)
            fullPrompt =
                CppBridgeToolCalling.buildFollowupPrompt(
                    originalPrompt = prompt,
                    tools = tools,
                    toolResult = result,
                    options = executionOptions,
                )
        }

        return ToolCallingResult(
            text = finalText,
            tool_calls = allToolCalls,
            tool_results = allToolResults,
            is_complete = true,
            iterations_used = maxIterations,
        )
    }

    /**
     * Continue generation after manual tool execution.
     *
     * Use this when auto_execute is false. After receiving a ToolCallingResult
     * with is_complete = false, execute the tool yourself, then call this to continue.
     *
     * @param previousPrompt The original user prompt
     * @param toolCall The tool call that was executed
     * @param toolResult The result of executing the tool
     * @param options Tool calling options for the continuation
     * @return Result of the continued generation
     */
    suspend fun continueWithToolResult(
        previousPrompt: String,
        toolCall: ToolCall,
        toolResult: ToolResult,
        options: ToolCallingOptions? = null,
    ): ToolCallingResult {
        // Build follow-up prompt using C++ (SINGLE SOURCE OF TRUTH)
        val tools = options?.tools?.ifEmpty { ToolRegistry.getAll() } ?: ToolRegistry.getAll()
        val effectiveOptions = options ?: ToolCallingOptions()

        val continuedPrompt =
            CppBridgeToolCalling.buildFollowupPrompt(
                originalPrompt = previousPrompt,
                tools = tools,
                toolResult =
                    toolResult.copy(
                        tool_call_id = toolResult.tool_call_id.ifBlank { toolCall.call_id ?: toolCall.id },
                        name = toolResult.name.ifBlank { toolCall.name },
                        call_id = toolResult.call_id ?: toolCall.call_id ?: toolCall.id,
                    ),
                options = effectiveOptions.copy(tools = tools),
            )

        val continuationOptions =
            ToolCallingOptions(
                tools = options?.tools ?: emptyList(),
                max_iterations =
                    maxOf(
                        0,
                        (options?.effectiveMaxIterations() ?: DEFAULT_TOOL_CALL_MAX_ITERATIONS) - 1,
                    ),
                auto_execute = options?.auto_execute ?: true,
                temperature = options?.temperature,
                max_tokens = options?.max_tokens,
                system_prompt = options?.system_prompt,
                replace_system_prompt = options?.replace_system_prompt ?: false,
                keep_tools_available = options?.keep_tools_available ?: false,
                format_hint = options?.effectiveToolFormatHint() ?: "default",
            )

        return generateWithTools(continuedPrompt, continuationOptions)
    }

    /**
     * Generate text through the generated proto LLM path.
     */
    private suspend fun generateAndCollect(
        prompt: String,
        temperature: Float?,
        maxTokens: Int?,
        toolOptions: ToolCallingOptions,
    ): String {
        val genOptions =
            LLMGenerationOptions(
                max_tokens = maxTokens ?: 1024,
                temperature = temperature ?: 0.7f,
                tool_calling = toolOptions,
            )

        return RunAnywhere.generate(prompt, genOptions).text
    }
}
