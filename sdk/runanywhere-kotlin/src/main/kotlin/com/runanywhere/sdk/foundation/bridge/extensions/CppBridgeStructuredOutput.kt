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
import ai.runanywhere.proto.v1.StructuredOutputStreamEvent
import ai.runanywhere.proto.v1.StructuredOutputValidation
import ai.runanywhere.proto.v1.StructuredOutputValidationRequest
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.NativeProtoProgressListener
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

    /**
     * Full structured-output generation: commons handles prompt preparation,
     * LLM generation, thinking-tag stripping, JSON extraction, and schema
     * validation. Returns the canonical [RAStructuredOutputResult].
     *
     * Mirrors Swift `CppBridge.StructuredOutput.generate(_:)`.
     */
    suspend fun generate(handle: Long, request: StructuredOutputRequest): RAStructuredOutputResult =
        decodeOrThrow(
            StructuredOutputResult.ADAPTER,
            RunAnywhereBridge.racStructuredOutputGenerateProto(
                handle,
                StructuredOutputRequest.ADAPTER.encode(request),
            ),
            "racStructuredOutputGenerateProto",
        )

    /**
     * Stream native structured-output generation. Commons emits one typed
     * [StructuredOutputStreamEvent] per callback invocation (TOKEN /
     * PARTIAL_JSON / COMPLETED / ERROR). The Kotlin layer simply decodes and
     * forwards — no StringBuilder accumulation, no JSON parsing.
     */
    fun generateStream(
        request: StructuredOutputRequest,
        onEvent: (StructuredOutputStreamEvent) -> Boolean,
    ) {
        val rc =
            RunAnywhereBridge.racStructuredOutputGenerateStreamProto(
                StructuredOutputRequest.ADAPTER.encode(request),
                NativeProtoProgressListener { bytes ->
                    onEvent(StructuredOutputStreamEvent.ADAPTER.decode(bytes))
                },
            )
        if (rc != RunAnywhereBridge.RAC_SUCCESS) {
            throw SDKException.operation(
                "racStructuredOutputGenerateStreamProto failed with rc=$rc",
            )
        }
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
