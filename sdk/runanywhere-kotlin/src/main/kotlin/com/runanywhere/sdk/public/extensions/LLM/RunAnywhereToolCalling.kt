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

suspend fun RunAnywhere.registerTool(definition: ToolDefinition, executor: ToolExecutor) {
    ToolCallingOrchestrator.registerTool(definition, executor)
}

suspend fun RunAnywhere.unregisterTool(toolName: String) {
    ToolCallingOrchestrator.unregisterTool(toolName)
}

suspend fun RunAnywhere.getRegisteredTools(): List<ToolDefinition> =
    ToolCallingOrchestrator.getRegisteredTools()

suspend fun RunAnywhere.clearTools() {
    ToolCallingOrchestrator.clearTools()
}

suspend fun RunAnywhere.executeTool(toolCall: ToolCall): ToolResult =
    ToolCallingOrchestrator.executeTool(toolCall)

suspend fun RunAnywhere.generateWithTools(
    prompt: String,
    options: RALLMGenerationOptions?,
    toolOptions: RAToolCallingOptions?,
    toolChoice: ToolChoiceMode?,
    forcedToolName: String?,
    validateCalls: Boolean? = null,
): RAToolCallingResult {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    // Swift parity (`RunAnywhere+ToolCalling.swift`): run the cold-start HTTP
    // bootstrap before touching the native run loop so a caller that only
    // completed Phase 1 init (`completeServicesInitialization` not yet run)
    // doesn't drive tool-calling against an uninitialized service layer.
    ensureServicesReady()
    // Swift parity: explicit `toolOptions` overrides any embedded
    // `options.tool_calling` payload, otherwise we fall back to the SDK
    // defaults via `toToolCallingOptions()` (which honors
    // `options?.tool_calling` when present).
    val baseToolOptions =
        toolOptions
            ?: options?.toToolCallingOptions()
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
    return ToolCallingOrchestrator.generateWithTools(
        prompt = prompt,
        options = effectiveToolOptions,
        llmOptions = options,
        validateCalls = validateCalls,
    )
}
