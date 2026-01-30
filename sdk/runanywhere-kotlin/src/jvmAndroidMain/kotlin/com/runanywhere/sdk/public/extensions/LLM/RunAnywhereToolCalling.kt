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

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.generateStream
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeToolCalling
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Thread-safe tool registry for tool registration and lookup.
 */
private object ToolRegistry {
    private val mutex = Mutex()
    private val tools = mutableMapOf<String, RegisteredTool>()

    suspend fun register(definition: ToolDefinition, executor: ToolExecutor) = mutex.withLock {
        tools[definition.name] = RegisteredTool(definition, executor)
    }

    suspend fun unregister(toolName: String) = mutex.withLock {
        tools.remove(toolName)
    }

    suspend fun getAll(): List<ToolDefinition> = mutex.withLock {
        tools.values.map { it.definition }
    }

    suspend fun get(toolName: String): RegisteredTool? = mutex.withLock {
        tools[toolName]
    }

    suspend fun clear() = mutex.withLock {
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
        executor: ToolExecutor
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
        val tool = ToolRegistry.get(toolCall.toolName)

        if (tool == null) {
            return ToolResult(
                toolName = toolCall.toolName,
                success = false,
                error = "Unknown tool: ${toolCall.toolName}",
                callId = toolCall.callId
            )
        }

        return try {
            val result = tool.executor(toolCall.arguments)
            ToolResult(
                toolName = toolCall.toolName,
                success = true,
                result = result,
                callId = toolCall.callId
            )
        } catch (e: Exception) {
            logger.error("Tool execution failed: ${e.message}")
            ToolResult(
                toolName = toolCall.toolName,
                success = false,
                error = e.message ?: "Unknown error",
                callId = toolCall.callId
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
     * 4. If tool call found and autoExecute is true, executes and continues
     * 5. Repeats until no more tool calls or maxToolCalls reached
     *
     * @param prompt The user's prompt
     * @param options Tool calling options
     * @return Result containing final text, all tool calls made, and their results
     */
    suspend fun generateWithTools(
        prompt: String,
        options: ToolCallingOptions? = null
    ): ToolCallingResult {
        // Ensure SDK is initialized
        require(RunAnywhere.isInitialized) { "SDK not initialized" }

        val opts = options ?: ToolCallingOptions()
        val registeredTools = ToolRegistry.getAll()
        val tools = opts.tools ?: registeredTools

        // Build system prompt using C++ (SINGLE SOURCE OF TRUTH)
        val systemPrompt = buildToolSystemPrompt(tools, opts)
        var fullPrompt = if (systemPrompt.isEmpty()) prompt else "$systemPrompt\n\nUser: $prompt"

        val allToolCalls = mutableListOf<ToolCall>()
        val allToolResults = mutableListOf<ToolResult>()
        var finalText = ""

        repeat(opts.maxToolCalls) { iteration ->
            logger.debug("Tool calling iteration $iteration")

            // Generate response
            val responseText = generateAndCollect(fullPrompt, opts.temperature, opts.maxTokens)

            // Parse for tool calls using C++ (SINGLE SOURCE OF TRUTH - NO FALLBACK)
            val (cleanText, toolCall) = CppBridgeToolCalling.parseToolCallToObject(responseText)
            finalText = cleanText

            if (toolCall == null) {
                logger.debug("No tool call found, generation complete")
                return ToolCallingResult(
                    text = finalText,
                    toolCalls = allToolCalls,
                    toolResults = allToolResults,
                    isComplete = true
                )
            }

            allToolCalls.add(toolCall)
            logger.info("Found tool call: ${toolCall.toolName}")

            if (!opts.autoExecute) {
                return ToolCallingResult(
                    text = finalText,
                    toolCalls = allToolCalls,
                    toolResults = emptyList(),
                    isComplete = false
                )
            }

            // Execute tool
            val result = executeTool(toolCall)
            allToolResults.add(result)
            logger.info("Tool ${toolCall.toolName} executed: ${if (result.success) "success" else "failed"}")

            // Build follow-up prompt using C++ (SINGLE SOURCE OF TRUTH)
            val toolResultJson = CppBridgeToolCalling.toolValueToJsonString(
                result.result ?: mapOf("error" to ToolValue.string(result.error ?: "Unknown error"))
            )

            fullPrompt = CppBridgeToolCalling.buildFollowupPrompt(
                originalPrompt = prompt,
                toolsPrompt = if (opts.keepToolsAvailable) CppBridgeToolCalling.formatToolsForPrompt(tools, opts.format) else null,
                toolName = toolCall.toolName,
                toolResultJson = toolResultJson,
                keepToolsAvailable = opts.keepToolsAvailable
            )
        }

        return ToolCallingResult(
            text = finalText,
            toolCalls = allToolCalls,
            toolResults = allToolResults,
            isComplete = true
        )
    }

    /**
     * Continue generation after manual tool execution.
     *
     * Use this when autoExecute is false. After receiving a ToolCallingResult
     * with isComplete: false, execute the tool yourself, then call this to continue.
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
        options: ToolCallingOptions? = null
    ): ToolCallingResult {
        val resultJson = CppBridgeToolCalling.toolValueToJsonString(
            toolResult.result ?: mapOf("error" to ToolValue.string(toolResult.error ?: "Unknown error"))
        )

        val continuedPrompt = """
            $previousPrompt

            Tool Result for ${toolCall.toolName}: $resultJson

            Based on the tool result, please provide your response:
        """.trimIndent()

        val continuationOptions = ToolCallingOptions(
            tools = options?.tools,
            maxToolCalls = (options?.maxToolCalls ?: 5) - 1,
            autoExecute = options?.autoExecute ?: true,
            temperature = options?.temperature,
            maxTokens = options?.maxTokens,
            systemPrompt = options?.systemPrompt,
            replaceSystemPrompt = options?.replaceSystemPrompt ?: false,
            keepToolsAvailable = options?.keepToolsAvailable ?: false,
            format = options?.format ?: ToolCallFormatName.DEFAULT
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
        options: ToolCallingOptions
    ): String {
        // Use C++ implementation for prompt formatting (SINGLE SOURCE OF TRUTH)
        // Pass the format from options to generate model-specific instructions
        val toolsPrompt = CppBridgeToolCalling.formatToolsForPrompt(tools, options.format)

        return when {
            options.replaceSystemPrompt && options.systemPrompt != null -> {
                options.systemPrompt
            }
            options.systemPrompt != null -> {
                "${options.systemPrompt}\n\n$toolsPrompt"
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
        maxTokens: Int?
    ): String {
        val genOptions = LLMGenerationOptions(
            maxTokens = maxTokens ?: 1024,
            temperature = temperature ?: 0.7f
        )

        val tokenFlow = RunAnywhere.generateStream(prompt, genOptions)

        val responseText = StringBuilder()
        tokenFlow.collect { token ->
            responseText.append(token)
        }

        return responseText.toString()
    }
}
