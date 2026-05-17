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
 *   Delegates to the platform actual, which owns only the host executor
 *   registry and callback invocation around generated proto data.
 *
 * *** ALL PARSING LOGIC IS IN C++ (rac_tool_calling.h) - NO KOTLIN FALLBACKS ***
 *
 * Mirrors Swift sdk/runanywhere-swift/.../RunAnywhere+ToolCalling.swift exactly.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.ToolChoiceMode
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.LLM.RAToolCallingOptions
import com.runanywhere.sdk.public.extensions.LLM.RAToolCallingResult
import com.runanywhere.sdk.public.extensions.LLM.ToolCall
import com.runanywhere.sdk.public.extensions.LLM.ToolDefinition
import com.runanywhere.sdk.public.extensions.LLM.ToolExecutor
import com.runanywhere.sdk.public.extensions.LLM.ToolResult
import com.runanywhere.sdk.public.types.RALLMGenerationOptions

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
 *             ToolParameter(
 *                 name = "location",
 *                 type = ToolParameterType.TOOL_PARAMETER_TYPE_STRING,
 *                 description = "City name",
 *                 required = true,
 *             ),
 *         ),
 *     ),
 * ) { args ->
 *     val location = args["location"]?.string ?: "Unknown"
 *     mapOf(
 *         "temperature" to RAToolValue.int(72),
 *         "condition" to RAToolValue.string("Sunny"),
 *     )
 * }
 * ```
 *
 * @param definition Tool definition (name, description, parameters)
 * @param executor Suspend closure that executes the tool with a typed argument
 *   map and returns a typed result map.
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
 * Orchestrates a generate -> parse -> execute -> loop cycle entirely in C++:
 * 1. Builds a system prompt describing available tools.
 * 2. Generates the LLM response.
 * 3. Parses output for tool calls.
 * 4. If a tool call is found and auto-execution is enabled, executes and
 *    continues until completion or [RAToolCallingOptions.max_iterations].
 *
 * Mirrors Swift's
 * `generateWithTools(prompt:options:toolOptions:) -> RAToolCallingResult`:
 *
 *  - `options.tool_calling` is consulted when `toolOptions` is null,
 *  - otherwise [RAToolCallingOptions.defaults] is used.
 *
 * @param prompt The user's prompt
 * @param options LLM generation options (optional)
 * @param toolOptions Tool-calling specific options. When non-null this
 *   overrides any `options.tool_calling` payload.
 * @param toolChoice Optional override that forces
 *   [RAToolCallingOptions.tool_choice]. Mirrors the OpenAI `tool_choice`
 *   knob: callers can pin the LLM to NONE / AUTO / SPECIFIC without having
 *   to manually mutate a `RAToolCallingOptions` proto. Mirrors Swift's
 *   `toolChoice:` parameter on `RunAnywhere.generateWithTools`.
 * @param forcedToolName Companion to `toolChoice = TOOL_CHOICE_MODE_SPECIFIC`
 *   — the tool name the LLM is forced to invoke. Overrides
 *   [RAToolCallingOptions.forced_tool_name] when non-null.
 * @return [RAToolCallingResult] with the final text, tool calls, and any
 *   executed tool results (matches the Swift surface).
 *
 * Note: `tool_choice` / `forced_tool_name` live on the `ToolCallingOptions`
 * proto (fields 13/14, idl/tool_calling.proto). They are applied here on
 * the effective options so future commons support (pass2-syn-006 parent)
 * automatically picks them up; the session-create request itself has
 * reserved-7-10 today, so end-to-end propagation to native parse/validate
 * helpers is pending the commons builder that snapshots options from the
 * request.
 */
expect suspend fun RunAnywhere.generateWithTools(
    prompt: String,
    options: RALLMGenerationOptions? = null,
    toolOptions: RAToolCallingOptions? = null,
    toolChoice: ToolChoiceMode? = null,
    forcedToolName: String? = null,
): RAToolCallingResult
