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

import ai.runanywhere.proto.v1.LLMGenerationOptions
import ai.runanywhere.proto.v1.LLMGenerationResult
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.LLM.RunAnywhereToolCalling
import com.runanywhere.sdk.public.extensions.LLM.ToolCall
import com.runanywhere.sdk.public.extensions.LLM.ToolDefinition
import com.runanywhere.sdk.public.extensions.LLM.ToolExecutor
import com.runanywhere.sdk.public.extensions.LLM.ToolResult
import com.runanywhere.sdk.public.extensions.LLM.toLLMGenerationResult
import com.runanywhere.sdk.public.extensions.LLM.toToolCallingOptions

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
    options: LLMGenerationOptions?,
): LLMGenerationResult {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    val toolOptions = options.toToolCallingOptions()
    val toolResult = RunAnywhereToolCalling.generateWithTools(prompt, toolOptions)
    return toolResult.toLLMGenerationResult()
}
