/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actuals for the `RunAnywhere.{registerTool, unregisterTool,
 * getRegisteredTools, clearTools, executeTool, generateWithTools,
 * continueWithToolResult}` extension surface.
 *
 * Round 2 KOTLIN: generateWithTools now accepts LLMGenerationOptions and
 * returns LLMGenerationResult per canonical spec. continueWithToolResult
 * is now 2-param (toolCallId, result) → LLMGenerationResult.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.LLMGenerationOptions
import ai.runanywhere.proto.v1.LLMGenerationResult
import ai.runanywhere.proto.v1.ToolCallingOptions
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeToolCalling
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

actual suspend fun RunAnywhere.continueWithToolResult(
    toolCallId: String,
    result: String,
): LLMGenerationResult {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    val continuationPrompt =
        CppBridgeToolCalling.buildFollowupPrompt(
            originalPrompt = "",
            tools = emptyList(),
            toolResult =
                ToolResult(
                    tool_call_id = toolCallId,
                    name = toolCallId,
                    result_json = result,
                    success = true,
                    call_id = toolCallId,
                ),
            options = ToolCallingOptions(),
        )
    return generate(
        prompt = continuationPrompt,
        options =
            LLMGenerationOptions(
                tool_calling =
                    ToolCallingOptions(
                        tools = emptyList(),
                        auto_execute = false,
                    ),
            ),
    )
}
