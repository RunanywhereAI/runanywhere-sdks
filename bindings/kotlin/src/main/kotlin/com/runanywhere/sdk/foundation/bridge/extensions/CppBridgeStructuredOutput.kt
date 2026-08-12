/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Generated-proto bridge for structured-output helper operations.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.StructuredOutputParseRequest
import ai.runanywhere.proto.v1.StructuredOutputPromptResult
import ai.runanywhere.proto.v1.StructuredOutputResult
import ai.runanywhere.proto.v1.StructuredOutputValidation
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RAStructuredOutputResult
import com.squareup.wire.Message
import com.squareup.wire.ProtoAdapter

/**
 * idl/structured_output.proto (API-realignment so-p2) deleted the dedicated
 * `StructuredOutputRequest` / `StructuredOutputValidationRequest` messages.
 * `StructuredOutputParseRequest` (request_id, text, options, metadata) is
 * now the sole request envelope shared by parse/validate/prepare-prompt —
 * `text` plays the role the old `prompt` field did (mirrors commons'
 * `rac_structured_output_prepare_prompt_proto` / `..._validate_proto`,
 * `structured_output.cpp`).
 */
object CppBridgeStructuredOutput {
    fun preparePrompt(request: StructuredOutputParseRequest): StructuredOutputPromptResult =
        decodeOrThrow(
            StructuredOutputPromptResult.ADAPTER,
            RunAnywhereBridge.racStructuredOutputPreparePromptProto(
                StructuredOutputParseRequest.ADAPTER.encode(request),
            ),
            "racStructuredOutputPreparePromptProto",
        )

    fun validate(request: StructuredOutputParseRequest): StructuredOutputValidation =
        decodeOrThrow(
            StructuredOutputValidation.ADAPTER,
            RunAnywhereBridge.racStructuredOutputValidateProto(
                StructuredOutputParseRequest.ADAPTER.encode(request),
            ),
            "racStructuredOutputValidateProto",
        )

    fun parse(request: StructuredOutputParseRequest): RAStructuredOutputResult =
        decodeOrThrow(
            StructuredOutputResult.ADAPTER,
            RunAnywhereBridge.racStructuredOutputParseProto(
                StructuredOutputParseRequest.ADAPTER.encode(request),
            ),
            "racStructuredOutputParseProto",
        )

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
