/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public tool-calling type aliases.
 *
 * Tool definitions, calls, values, options, and results are generated from
 * idl/tool_calling.proto. Kotlin keeps only the host executor callback and
 * in-memory registry adapter because executing app callbacks is platform-owned.
 */

package com.runanywhere.sdk.public.extensions.LLM

import ai.runanywhere.proto.v1.LLMGenerationOptions
import ai.runanywhere.proto.v1.LLMGenerationResult

typealias ToolValue = ai.runanywhere.proto.v1.ToolValue
typealias ToolValueArray = ai.runanywhere.proto.v1.ToolValueArray
typealias ToolValueObject = ai.runanywhere.proto.v1.ToolValueObject
typealias ToolParameterType = ai.runanywhere.proto.v1.ToolParameterType
typealias ToolParameter = ai.runanywhere.proto.v1.ToolParameter
typealias ToolDefinition = ai.runanywhere.proto.v1.ToolDefinition
typealias ToolCall = ai.runanywhere.proto.v1.ToolCall
typealias ToolResult = ai.runanywhere.proto.v1.ToolResult
typealias ToolCallFormatName = ai.runanywhere.proto.v1.ToolCallFormatName
typealias ToolCallingOptions = ai.runanywhere.proto.v1.ToolCallingOptions
typealias ToolCallingResult = ai.runanywhere.proto.v1.ToolCallingResult

/**
 * Function type for host tool executors.
 *
 * The SDK owns only callback invocation. Tool calls and results use generated
 * proto messages; argument JSON parsing and result JSON construction belong to
 * the host tool implementation.
 */
typealias ToolExecutor = suspend (ToolCall) -> ToolResult

internal data class RegisteredTool(
    val definition: ToolDefinition,
    val executor: ToolExecutor,
)

internal const val DEFAULT_TOOL_CALL_MAX_ITERATIONS = 5

internal fun LLMGenerationOptions?.toToolCallingOptions(): ToolCallingOptions {
    val generationOptions = this
    val providedToolOptions = generationOptions?.tool_calling
    val base = providedToolOptions ?: ToolCallingOptions()
    return base.copy(
        max_iterations =
            base.max_iterations.takeIf { it > 0 }
                ?: base.max_tool_calls?.takeIf { it > 0 }
                ?: if (providedToolOptions == null) DEFAULT_TOOL_CALL_MAX_ITERATIONS else 0,
        auto_execute = if (providedToolOptions == null) true else base.auto_execute,
        temperature =
            base.temperature
                ?: generationOptions?.temperature?.takeUnless { it == 0f },
        max_tokens =
            base.max_tokens
                ?: generationOptions?.max_tokens?.takeIf { it > 0 },
        system_prompt = base.system_prompt ?: generationOptions?.system_prompt,
        format_hint = base.effectiveToolFormatHint(),
    )
}

internal fun ToolCallingOptions.effectiveMaxIterations(): Int =
    max_iterations.takeIf { it > 0 }
        ?: max_tool_calls?.takeIf { it > 0 }
        ?: DEFAULT_TOOL_CALL_MAX_ITERATIONS

internal fun ToolCallingOptions.effectiveToolFormatHint(): String =
    format_hint.ifBlank { format.toToolFormatHint() }.ifBlank { "default" }

internal fun ToolCallingResult.toLLMGenerationResult(modelUsed: String = ""): LLMGenerationResult =
    LLMGenerationResult(
        text = text,
        model_used = modelUsed,
        finish_reason =
            when {
                error_message != null || error_code != 0 -> "error"
                is_complete -> "stop"
                else -> "tool_calls"
            },
        error_message = error_message,
        error_code = error_code,
        tool_calls = tool_calls,
        tool_results = tool_results,
    )

private fun ToolCallFormatName?.toToolFormatHint(): String =
    when (this) {
        ToolCallFormatName.TOOL_CALL_FORMAT_NAME_JSON -> "default"
        ToolCallFormatName.TOOL_CALL_FORMAT_NAME_XML -> "xml"
        ToolCallFormatName.TOOL_CALL_FORMAT_NAME_NATIVE -> "native"
        ToolCallFormatName.TOOL_CALL_FORMAT_NAME_PYTHONIC -> "pythonic"
        ToolCallFormatName.TOOL_CALL_FORMAT_NAME_OPENAI_FUNCTIONS -> "openai"
        ToolCallFormatName.TOOL_CALL_FORMAT_NAME_HERMES -> "hermes"
        else -> ""
    }
