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

import ai.runanywhere.proto.v1.ToolCallingOptions
import ai.runanywhere.proto.v1.ToolPromptFormatRequest
import ai.runanywhere.proto.v1.ToolPromptFormatResult
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RAToolDefinition
import com.runanywhere.sdk.public.types.RAToolResult
import com.squareup.wire.Message
import com.squareup.wire.ProtoAdapter

object CppBridgeToolCalling {
    fun buildFollowupPrompt(
        originalPrompt: String,
        tools: List<RAToolDefinition>,
        toolResult: RAToolResult,
        options: ToolCallingOptions,
    ): String =
        formattedPrompt(
            ToolPromptFormatRequest(
                user_prompt = originalPrompt,
                options = options.bridgeOptions(tools),
                tool_results = listOf(toolResult),
            ),
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

    private fun formatPrompt(request: ToolPromptFormatRequest): ToolPromptFormatResult =
        decodeOrThrow(
            ToolPromptFormatResult.ADAPTER,
            RunAnywhereBridge.racToolCallFormatPromptProto(
                ToolPromptFormatRequest.ADAPTER.encode(request),
            ),
            "racToolCallFormatPromptProto",
        )

    private fun ToolCallingOptions.bridgeOptions(
        toolsOverride: List<RAToolDefinition>? = null,
    ): ToolCallingOptions = copy(tools = toolsOverride ?: tools)

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
