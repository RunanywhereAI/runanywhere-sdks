/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for tool calling (function calling) with LLMs.
 * Allows LLMs to request external actions (API calls, device functions, etc.)
 *
 * ARCHITECTURE:
 * - CppBridgeToolCalling: C++ bridge for parsing <tool_call> tags
 *   (SINGLE SOURCE OF TRUTH; lives under foundation/bridge/extensions).
 * - This file: extension-function surface on `RunAnywhere` matching Swift's
 *   `RunAnywhere.registerTool(...)` / `generateWithTools(...)` / etc.
 *   Delegates to the platform actual which forwards to the existing
 *   `com.runanywhere.sdk.public.extensions.LLM.RunAnywhereToolCalling`
 *   object (registry + orchestration loop already lives there).
 *
 * *** ALL PARSING LOGIC IS IN C++ (rac_tool_calling.h) - NO KOTLIN FALLBACKS ***
 *
 * Mirrors Swift sdk/runanywhere-swift/.../RunAnywhere+ToolCalling.swift exactly.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.LLM.ToolCall
import com.runanywhere.sdk.public.extensions.LLM.ToolCallingOptions
import com.runanywhere.sdk.public.extensions.LLM.ToolCallingResult
import com.runanywhere.sdk.public.extensions.LLM.ToolDefinition
import com.runanywhere.sdk.public.extensions.LLM.ToolExecutor
import com.runanywhere.sdk.public.extensions.LLM.ToolResult

// =============================================================================
// TOOL REGISTRATION
// =============================================================================

/**
 * Register a tool that the LLM can use.
 *
 * Tools are stored in-memory and available for all subsequent
 * `generateWithTools` calls. Executors run in Kotlin and have full access
 * to JVM/Android APIs (networking, device, etc.).
 *
 * Example:
 * ```kotlin
 * RunAnywhere.registerTool(
 *     ToolDefinition(
 *         name = "get_weather",
 *         description = "Gets current weather for a location",
 *         parameters = listOf(
 *             ToolParameter("location", ToolParameterType.STRING, "City name"),
 *         ),
 *     ),
 * ) { args ->
 *     val location = args["location"]?.stringValue ?: "Unknown"
 *     mapOf("temperature" to ToolValue.number(72), "condition" to ToolValue.string("Sunny"))
 * }
 * ```
 *
 * @param definition Tool definition (name, description, parameters)
 * @param executor Suspend closure that executes the tool
 */
expect suspend fun RunAnywhere.registerTool(
    definition: ToolDefinition,
    executor: ToolExecutor,
)

/**
 * Unregister a tool by name.
 *
 * @param toolName The name of the tool to remove
 */
expect suspend fun RunAnywhere.unregisterTool(toolName: String)

/**
 * Get all registered tool definitions.
 *
 * @return List of registered tool definitions
 */
expect suspend fun RunAnywhere.getRegisteredTools(): List<ToolDefinition>

/** Clear all registered tools. */
expect suspend fun RunAnywhere.clearTools()

// =============================================================================
// TOOL EXECUTION
// =============================================================================

/**
 * Execute a tool call against the registry.
 *
 * @param toolCall The tool call to execute
 * @return Result of the tool execution
 */
expect suspend fun RunAnywhere.executeTool(toolCall: ToolCall): ToolResult

// =============================================================================
// GENERATE WITH TOOLS
// =============================================================================

/**
 * Generates a response with tool-calling support.
 *
 * Orchestrates a generate -> parse -> execute -> loop cycle:
 * 1. Builds a system prompt describing available tools (via C++ bridge).
 * 2. Generates LLM response.
 * 3. Parses output for `<tool_call>` tags (via C++ bridge).
 * 4. If a tool call is found and `autoExecute` is true, executes and continues.
 * 5. Repeats until no more tool calls or `maxToolCalls` is reached.
 *
 * @param prompt The user's prompt
 * @param options Tool-calling options (tools, maxToolCalls, autoExecute, etc.)
 * @return Result containing final text, all tool calls made, and their results
 */
expect suspend fun RunAnywhere.generateWithTools(
    prompt: String,
    options: ToolCallingOptions? = null,
): ToolCallingResult

/**
 * Continue generation after a manual tool execution.
 *
 * Use this when `autoExecute` is false. After receiving a `ToolCallingResult`
 * with `isComplete == false`, execute the tool yourself, then call this to
 * continue.
 *
 * @param previousPrompt The original user prompt
 * @param toolCall The tool call that was executed
 * @param toolResult The result of executing the tool
 * @param options Tool-calling options for the continuation
 * @return Result of the continued generation
 */
expect suspend fun RunAnywhere.continueWithToolResult(
    previousPrompt: String,
    toolCall: ToolCall,
    toolResult: ToolResult,
    options: ToolCallingOptions? = null,
): ToolCallingResult
