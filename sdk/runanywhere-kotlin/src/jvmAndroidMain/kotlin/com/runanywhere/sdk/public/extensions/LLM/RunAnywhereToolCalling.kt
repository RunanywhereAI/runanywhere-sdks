/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for tool calling (function calling) with LLMs.
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
import com.runanywhere.sdk.public.extensions.generateStream
import kotlinx.coroutines.flow.takeWhile
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull

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
 * Tool calling extension for RunAnywhere.
 */
object RunAnywhereToolCalling {
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

        if (tool == null) {
            return ToolResult(
                tool_call_id = toolCall.id,
                name = toolCall.name,
                error = "Unknown tool: ${toolCall.name}",
            )
        }

        return try {
            val arguments = CppBridgeToolCalling.parseArgumentsJson(toolCall.arguments_json.ifBlank { "{}" })
            val result = tool.executor(arguments)
            ToolResult(
                tool_call_id = toolCall.id,
                name = toolCall.name,
                result_json = CppBridgeToolCalling.toolValueToJsonString(result),
            )
        } catch (e: Exception) {
            logger.error("Tool execution failed: ${e.message}")
            ToolResult(
                tool_call_id = toolCall.id,
                name = toolCall.name,
                error = e.message ?: "Unknown error",
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

        // Build system prompt using C++ (SINGLE SOURCE OF TRUTH)
        val systemPrompt = buildToolSystemPrompt(tools, opts)
        var fullPrompt = if (systemPrompt.isEmpty()) prompt else "$systemPrompt\n\nUser: $prompt"

        val allToolCalls = mutableListOf<ToolCall>()
        val allToolResults = mutableListOf<ToolResult>()
        var finalText = ""

        val maxIterations = opts.max_iterations.takeIf { it > 0 } ?: 5
        repeat(maxIterations) { iteration ->
            logger.debug("Tool calling iteration $iteration")

            // Generate response
            val responseText = generateAndCollect(fullPrompt, opts.temperature, opts.max_tokens)

            // Parse for tool calls using C++ (SINGLE SOURCE OF TRUTH - NO FALLBACK)
            val (cleanText, toolCall) = CppBridgeToolCalling.parseToolCallToObject(responseText)
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

            if (!opts.auto_execute) {
                return ToolCallingResult(
                    text = finalText,
                    tool_calls = allToolCalls,
                    tool_results = emptyList(),
                    is_complete = false,
                    iterations_used = iteration + 1,
                )
            }

            // Execute tool
            val result = executeTool(toolCall)
            allToolResults.add(result)
            logger.info("Tool ${toolCall.name} executed: ${if (result.error.isNullOrBlank()) "success" else "failed"}")

            // Build follow-up prompt using C++ (SINGLE SOURCE OF TRUTH)
            val toolResultJson =
                result.result_json.ifBlank {
                    CppBridgeToolCalling.toolValueToJsonString(
                        mapOf("error" to ToolValue(string_value = result.error ?: "Unknown error")),
                    )
                }

            fullPrompt =
                CppBridgeToolCalling.buildFollowupPrompt(
                    originalPrompt = prompt,
                    toolsPrompt = if (opts.keep_tools_available) CppBridgeToolCalling.formatToolsForPrompt(tools, opts.format_hint) else null,
                    toolName = toolCall.name,
                    toolResultJson = toolResultJson,
                    keepToolsAvailable = opts.keep_tools_available,
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
        val resultJson =
            toolResult.result_json.ifBlank {
                CppBridgeToolCalling.toolValueToJsonString(
                    mapOf("error" to ToolValue(string_value = toolResult.error ?: "Unknown error")),
                )
            }

        // Build follow-up prompt using C++ (SINGLE SOURCE OF TRUTH)
        val tools = options?.tools?.ifEmpty { ToolRegistry.getAll() } ?: ToolRegistry.getAll()
        val toolsPrompt =
            if (options?.keep_tools_available == true) {
                CppBridgeToolCalling.formatToolsForPrompt(tools, options.format_hint)
            } else {
                null
            }

        val continuedPrompt =
            CppBridgeToolCalling.buildFollowupPrompt(
                originalPrompt = previousPrompt,
                toolsPrompt = toolsPrompt,
                toolName = toolCall.name,
                toolResultJson = resultJson,
                keepToolsAvailable = options?.keep_tools_available ?: false,
            )

        val continuationOptions =
            ToolCallingOptions(
                tools = options?.tools ?: emptyList(),
                max_iterations = maxOf(0, (options?.max_iterations ?: 5) - 1),
                auto_execute = options?.auto_execute ?: true,
                temperature = options?.temperature,
                max_tokens = options?.max_tokens,
                system_prompt = options?.system_prompt,
                replace_system_prompt = options?.replace_system_prompt ?: false,
                keep_tools_available = options?.keep_tools_available ?: false,
                format_hint = options?.format_hint ?: "default",
            )

        return generateWithTools(continuedPrompt, continuationOptions)
    }

    // ========================================================================
    // PRIVATE HELPERS
    // ========================================================================

    /**
     * Builds the system prompt with tool definitions using C++ implementation.
     */
    private fun buildToolSystemPrompt(
        tools: List<ToolDefinition>,
        options: ToolCallingOptions,
    ): String {
        // Use C++ implementation for prompt formatting (SINGLE SOURCE OF TRUTH)
        // Pass the format from options to generate model-specific instructions
        val toolsPrompt = CppBridgeToolCalling.formatToolsForPrompt(tools, options.format_hint)

        return when {
            options.replace_system_prompt && options.system_prompt != null -> {
                options.system_prompt
            }
            options.system_prompt != null -> {
                "${options.system_prompt}\n\n$toolsPrompt"
            }
            else -> {
                toolsPrompt
            }
        }
    }

    /**
     * Generate text using streaming and collect all tokens into a single string.
     */
    private suspend fun generateAndCollect(
        prompt: String,
        temperature: Float?,
        maxTokens: Int?,
    ): String {
        val genOptions =
            LLMGenerationOptions(
                max_tokens = maxTokens ?: 1024,
                temperature = temperature ?: 0.7f,
            )

        // v2 close-out Phase G-2: generateStream now emits LLMStreamEvent;
        // collect token text off each non-terminal event.
        val eventFlow = RunAnywhere.generateStream(prompt, genOptions)

        val responseText = StringBuilder()
        // B-AK-7-002: bound the collect with a timeout so a missing is_final never hangs the UI.
        withTimeoutOrNull(60_000L) {
            eventFlow
                .takeWhile { !it.is_final }
                .collect { event ->
                    if (event.token.isNotEmpty()) {
                        responseText.append(event.token)
                    }
                    if (event.is_final && event.error_message.isNotEmpty()) {
                        throw com.runanywhere.sdk.foundation.errors.SDKException
                            .llm(event.error_message)
                    }
                }
        }

        return responseText.toString()
    }
}
