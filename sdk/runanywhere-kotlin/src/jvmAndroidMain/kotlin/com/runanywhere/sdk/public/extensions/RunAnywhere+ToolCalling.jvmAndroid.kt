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
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLLM
import com.runanywhere.sdk.foundation.errors.SDKException
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
    options: LLMGenerationOptions?,
): LLMGenerationResult {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    // Delegate through the existing tool-calling orchestration loop but wrap
    // the result into the canonical LLMGenerationResult shape.
    val toolOptions =
        ToolCallingOptions(
            autoExecute = true,
        )
    val tcResult: ToolCallingResult = RunAnywhereToolCalling.generateWithTools(prompt, toolOptions)
    return LLMGenerationResult(
        text = tcResult.text,
        model_used = CppBridgeLLM.getLoadedModelId() ?: "unknown",
    )
}

actual suspend fun RunAnywhere.continueWithToolResult(
    toolCallId: String,
    result: String,
): LLMGenerationResult {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    // Build a continuation prompt with the tool result and generate.
    val continuationPrompt = "[Tool result for $toolCallId]: $result"
    val config = CppBridgeLLM.GenerationConfig.DEFAULT
    val cppResult = CppBridgeLLM.generate(continuationPrompt, config)
    return LLMGenerationResult(
        text = cppResult.text,
        model_used = CppBridgeLLM.getLoadedModelId() ?: "unknown",
        tokens_generated = cppResult.tokensGenerated,
        tokens_per_second = cppResult.tokensPerSecond.toDouble(),
    )
}
