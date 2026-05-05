/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Generated-proto bridge for tool calling.
 *
 * Kotlin owns only host callback registration and invocation. Tool-call
 * parsing, prompt formatting, and validation are forwarded to commons via
 * serialized generated proto request/result messages.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.ToolCall
import ai.runanywhere.proto.v1.ToolCallFormatName
import ai.runanywhere.proto.v1.ToolCallValidationRequest
import ai.runanywhere.proto.v1.ToolCallValidationResult
import ai.runanywhere.proto.v1.ToolCallingOptions
import ai.runanywhere.proto.v1.ToolDefinition
import ai.runanywhere.proto.v1.ToolParseRequest
import ai.runanywhere.proto.v1.ToolParseResult
import ai.runanywhere.proto.v1.ToolPromptFormatRequest
import ai.runanywhere.proto.v1.ToolPromptFormatResult
import ai.runanywhere.proto.v1.ToolResult
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.extensions.LLM.effectiveToolFormatHint
import com.squareup.wire.Message
import com.squareup.wire.ProtoAdapter

object CppBridgeToolCalling {
    fun parseToolCalls(
        llmOutput: String,
        options: ToolCallingOptions? = null,
    ): ToolParseResult =
        decodeOrThrow(
            ToolParseResult.ADAPTER,
            RunAnywhereBridge.racToolCallParseProto(
                ToolParseRequest.ADAPTER.encode(
                    ToolParseRequest(
                        text = llmOutput,
                        options = options?.bridgeOptions(),
                    ),
                ),
            ),
            "racToolCallParseProto",
        )

    fun parseToolCallToObject(
        llmOutput: String,
        options: ToolCallingOptions? = null,
    ): Pair<String, ToolCall?> {
        val result = parseToolCalls(llmOutput, options)
        if (result.error_code != 0) {
            throw SDKException.operation(
                result.error_message ?: "Tool-call parsing failed: ${result.error_code}",
            )
        }
        return result.remaining_text to result.tool_calls.firstOrNull().takeIf { result.has_tool_call }
    }

    fun formatToolsForPrompt(
        tools: List<ToolDefinition>,
        formatHint: String = "",
    ): String {
        if (tools.isEmpty()) return ""
        val options =
            ToolCallingOptions(
                tools = tools,
                format_hint = formatHint,
            ).bridgeOptions()
        return formattedPrompt(
            ToolPromptFormatRequest(
                options = options,
            ),
        )
    }

    fun buildInitialPrompt(
        userPrompt: String,
        tools: List<ToolDefinition>,
        options: ToolCallingOptions,
    ): String {
        if (tools.isEmpty()) return userPrompt
        return formattedPrompt(
            ToolPromptFormatRequest(
                user_prompt = userPrompt,
                options = options.bridgeOptions(tools),
            ),
        )
    }

    fun buildFollowupPrompt(
        originalPrompt: String,
        tools: List<ToolDefinition>,
        toolResult: ToolResult,
        options: ToolCallingOptions,
    ): String =
        formattedPrompt(
            ToolPromptFormatRequest(
                user_prompt = originalPrompt,
                options = options.bridgeOptions(tools),
                tool_results = listOf(toolResult),
            ),
        )

    fun validateToolCall(
        toolCall: ToolCall,
        tools: List<ToolDefinition>,
        options: ToolCallingOptions,
    ): ToolCallValidationResult =
        decodeOrThrow(
            ToolCallValidationResult.ADAPTER,
            RunAnywhereBridge.racToolCallValidateProto(
                ToolCallValidationRequest.ADAPTER.encode(
                    ToolCallValidationRequest(
                        tool_call = toolCall,
                        options = options.bridgeOptions(tools),
                    ),
                ),
            ),
            "racToolCallValidateProto",
        )

    fun formatPrompt(request: ToolPromptFormatRequest): ToolPromptFormatResult =
        decodeOrThrow(
            ToolPromptFormatResult.ADAPTER,
            RunAnywhereBridge.racToolCallFormatPromptProto(
                ToolPromptFormatRequest.ADAPTER.encode(request),
            ),
            "racToolCallFormatPromptProto",
        )

    private fun formattedPrompt(request: ToolPromptFormatRequest): String {
        val result = formatPrompt(request)
        if (result.error_code != 0) {
            throw SDKException.operation(
                result.error_message ?: "Tool prompt formatting failed: ${result.error_code}",
            )
        }
        return result.formatted_prompt
    }

    private fun ToolCallingOptions.bridgeOptions(
        toolsOverride: List<ToolDefinition>? = null,
    ): ToolCallingOptions {
        val hint = effectiveToolFormatHint()
        return copy(
            tools = toolsOverride ?: tools,
            format_hint = hint,
            format = format ?: hint.toToolCallFormatName(),
        )
    }

    private fun String.toToolCallFormatName(): ToolCallFormatName =
        when (lowercase()) {
            "lfm2", "lfm", "liquid", "pythonic", "hermes" ->
                ToolCallFormatName.TOOL_CALL_FORMAT_NAME_PYTHONIC
            "openai", "openai_functions", "openai-functions" ->
                ToolCallFormatName.TOOL_CALL_FORMAT_NAME_OPENAI_FUNCTIONS
            "xml" -> ToolCallFormatName.TOOL_CALL_FORMAT_NAME_XML
            "native" -> ToolCallFormatName.TOOL_CALL_FORMAT_NAME_NATIVE
            else -> ToolCallFormatName.TOOL_CALL_FORMAT_NAME_JSON
        }

    private fun <M : Message<M, *>> decodeOrThrow(
        adapter: ProtoAdapter<M>,
        bytes: ByteArray?,
        operation: String,
    ): M {
        val payload = bytes ?: throw SDKException.operation("$operation returned null")
        return try {
            adapter.decode(payload)
        } catch (e: Exception) {
            throw SDKException.operation("Failed to decode $operation result: ${e.message}")
        }
    }
}
