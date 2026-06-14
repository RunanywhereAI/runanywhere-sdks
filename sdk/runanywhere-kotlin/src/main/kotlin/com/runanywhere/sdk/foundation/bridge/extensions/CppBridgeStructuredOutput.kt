/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Generated-proto bridge for structured-output helper operations.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.StructuredOutputParseRequest
import ai.runanywhere.proto.v1.StructuredOutputPromptResult
import ai.runanywhere.proto.v1.StructuredOutputRequest
import ai.runanywhere.proto.v1.StructuredOutputResult
import ai.runanywhere.proto.v1.StructuredOutputValidation
import ai.runanywhere.proto.v1.StructuredOutputValidationRequest
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RAStructuredOutputResult
import com.squareup.wire.Message
import com.squareup.wire.ProtoAdapter

object CppBridgeStructuredOutput {
    fun preparePrompt(request: StructuredOutputRequest): StructuredOutputPromptResult =
        decodeOrThrow(
            StructuredOutputPromptResult.ADAPTER,
            RunAnywhereBridge.racStructuredOutputPreparePromptProto(
                StructuredOutputRequest.ADAPTER.encode(request),
            ),
            "racStructuredOutputPreparePromptProto",
        )

    fun validate(request: StructuredOutputValidationRequest): StructuredOutputValidation =
        decodeOrThrow(
            StructuredOutputValidation.ADAPTER,
            RunAnywhereBridge.racStructuredOutputValidateProto(
                StructuredOutputValidationRequest.ADAPTER.encode(request),
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
