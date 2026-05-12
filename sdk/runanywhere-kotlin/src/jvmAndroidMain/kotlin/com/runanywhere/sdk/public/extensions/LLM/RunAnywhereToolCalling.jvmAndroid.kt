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
import com.runanywhere.sdk.public.extensions.LLM.ToolCall
import com.runanywhere.sdk.public.extensions.LLM.ToolCallingOrchestrator
import com.runanywhere.sdk.public.extensions.LLM.ToolDefinition
import com.runanywhere.sdk.public.extensions.LLM.ToolExecutor
import com.runanywhere.sdk.public.extensions.LLM.ToolResult
import com.runanywhere.sdk.public.extensions.LLM.toLLMGenerationResult
import com.runanywhere.sdk.public.extensions.LLM.toToolCallingOptions
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import com.runanywhere.sdk.public.types.RALLMGenerationResult

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
): RALLMGenerationResult {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    val toolOptions = options.toToolCallingOptions()
    val toolResult = ToolCallingOrchestrator.generateWithTools(prompt, toolOptions)
    return toolResult.toLLMGenerationResult()
}
