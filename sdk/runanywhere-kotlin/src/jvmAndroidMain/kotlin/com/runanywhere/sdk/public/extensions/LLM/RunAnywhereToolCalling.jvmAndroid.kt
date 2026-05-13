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
): RAToolCallingResult {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    // Swift parity: explicit `toolOptions` overrides any embedded
    // `options.tool_calling` payload, otherwise we fall back to the SDK
    // defaults via `toToolCallingOptions()` (which honors
    // `options?.tool_calling` when present).
    val effectiveToolOptions =
        toolOptions
            ?: options?.tool_calling
            ?: options
                .toToolCallingOptions()
                .takeIf { options != null }
            ?: RAToolCallingOptions.defaults()
    return ToolCallingOrchestrator.generateWithTools(prompt, effectiveToolOptions)
}
