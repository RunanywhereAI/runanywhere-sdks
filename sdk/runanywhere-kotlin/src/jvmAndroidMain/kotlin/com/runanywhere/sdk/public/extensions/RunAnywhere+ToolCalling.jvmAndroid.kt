/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actuals for the `RunAnywhere.{registerTool, unregisterTool,
 * getRegisteredTools, clearTools, executeTool, generateWithTools,
 * continueWithToolResult}` extension surface.
 *
 * These are thin shims that forward to the existing object-style
 * `com.runanywhere.sdk.public.extensions.LLM.RunAnywhereToolCalling` —
 * one registry, one orchestration loop, two API shapes (object + extension).
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.LLM.RunAnywhereToolCalling
import com.runanywhere.sdk.public.extensions.LLM.ToolCall
import com.runanywhere.sdk.public.extensions.LLM.ToolCallingOptions
import com.runanywhere.sdk.public.extensions.LLM.ToolCallingResult
import com.runanywhere.sdk.public.extensions.LLM.ToolDefinition
import com.runanywhere.sdk.public.extensions.LLM.ToolExecutor
import com.runanywhere.sdk.public.extensions.LLM.ToolResult

actual suspend fun RunAnywhere.registerTool(definition: ToolDefinition, executor: ToolExecutor) {
    RunAnywhereToolCalling.registerTool(definition, executor)
}

actual suspend fun RunAnywhere.unregisterTool(toolName: String) {
    RunAnywhereToolCalling.unregisterTool(toolName)
}

actual suspend fun RunAnywhere.getRegisteredTools(): List<ToolDefinition> =
    RunAnywhereToolCalling.getRegisteredTools()

actual suspend fun RunAnywhere.clearTools() {
    RunAnywhereToolCalling.clearTools()
}

actual suspend fun RunAnywhere.executeTool(toolCall: ToolCall): ToolResult =
    RunAnywhereToolCalling.executeTool(toolCall)

actual suspend fun RunAnywhere.generateWithTools(
    prompt: String,
    options: ToolCallingOptions?,
): ToolCallingResult =
    RunAnywhereToolCalling.generateWithTools(prompt, options)

actual suspend fun RunAnywhere.continueWithToolResult(
    previousPrompt: String,
    toolCall: ToolCall,
    toolResult: ToolResult,
    options: ToolCallingOptions?,
): ToolCallingResult =
    RunAnywhereToolCalling.continueWithToolResult(previousPrompt, toolCall, toolResult, options)
