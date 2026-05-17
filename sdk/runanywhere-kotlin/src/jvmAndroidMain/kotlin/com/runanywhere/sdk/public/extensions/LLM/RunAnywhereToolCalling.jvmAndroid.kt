/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actuals for the `RunAnywhere.{registerTool, unregisterTool,
 * getRegisteredTools, clearTools, executeTool, generateWithTools}`
 * extension surface.
 *
 * Mirrors Swift `RunAnywhere+ToolCalling.swift`.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.ToolChoiceMode
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.LLM.RAToolCallingOptions
import com.runanywhere.sdk.public.extensions.LLM.RAToolCallingResult
import com.runanywhere.sdk.public.extensions.LLM.ToolCall
import com.runanywhere.sdk.public.extensions.LLM.ToolCallingOrchestrator
import com.runanywhere.sdk.public.extensions.LLM.ToolDefinition
import com.runanywhere.sdk.public.extensions.LLM.ToolExecutor
import com.runanywhere.sdk.public.extensions.LLM.ToolResult
import com.runanywhere.sdk.public.extensions.LLM.defaults
import com.runanywhere.sdk.public.extensions.LLM.toToolCallingOptions
import com.runanywhere.sdk.public.types.RALLMGenerationOptions

actual suspend fun RunAnywhere.registerTool(definition: ToolDefinition, executor: ToolExecutor) {
    ToolCallingOrchestrator.registerTool(definition, executor)
}

actual suspend fun RunAnywhere.unregisterTool(toolName: String) {
    ToolCallingOrchestrator.unregisterTool(toolName)
}

actual suspend fun RunAnywhere.getRegisteredTools(): List<ToolDefinition> =
    ToolCallingOrchestrator.getRegisteredTools()

actual suspend fun RunAnywhere.clearTools() {
    ToolCallingOrchestrator.clearTools()
}

actual suspend fun RunAnywhere.executeTool(toolCall: ToolCall): ToolResult =
    ToolCallingOrchestrator.executeTool(toolCall)

actual suspend fun RunAnywhere.generateWithTools(
    prompt: String,
    options: RALLMGenerationOptions?,
    toolOptions: RAToolCallingOptions?,
    toolChoice: ToolChoiceMode?,
    forcedToolName: String?,
): RAToolCallingResult {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    // Swift parity: explicit `toolOptions` overrides any embedded
    // `options.tool_calling` payload, otherwise we fall back to the SDK
    // defaults via `toToolCallingOptions()` (which honors
    // `options?.tool_calling` when present).
    val baseToolOptions =
        toolOptions
            ?: options?.tool_calling
            ?: options
                .toToolCallingOptions()
                .takeIf { options != null }
            ?: RAToolCallingOptions.defaults()
    // Apply `toolChoice` / `forcedToolName` overrides on top of the resolved
    // options. Mirrors Swift's `RunAnywhere+ToolCalling.swift` `tcOpts`
    // mutation. These live on `ToolCallingOptions` proto (fields 13/14) so
    // they flow into the same per-options snapshot the commons run-loop /
    // session helpers consume once they start honoring them.
    val effectiveToolOptions =
        baseToolOptions.copy(
            tool_choice = toolChoice ?: baseToolOptions.tool_choice,
            forced_tool_name = forcedToolName ?: baseToolOptions.forced_tool_name,
        )
    return ToolCallingOrchestrator.generateWithTools(prompt, effectiveToolOptions)
}
