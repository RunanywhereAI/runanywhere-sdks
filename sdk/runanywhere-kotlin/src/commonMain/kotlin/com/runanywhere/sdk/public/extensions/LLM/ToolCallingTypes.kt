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
 * The SDK owns only callback invocation. Tool argument/result data uses the
 * generated proto [ToolValue] tree.
 */
typealias ToolExecutor = suspend (Map<String, ToolValue>) -> Map<String, ToolValue>

internal data class RegisteredTool(
    val definition: ToolDefinition,
    val executor: ToolExecutor,
)
