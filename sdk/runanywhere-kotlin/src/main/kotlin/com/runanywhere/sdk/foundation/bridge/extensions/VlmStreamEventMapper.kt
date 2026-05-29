/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Maps canonical [VLMStreamEvent] payloads from `rac_vlm_process_stream_proto`
 * into [SDKEvent] generation envelopes for the public `processImageStream` API.
 *
 * C++ commons emits VLMStreamEvent on the stream callback (see
 * rac_vlm_proto_abi.cpp). React Native decodes VLMStreamEvent directly; Kotlin
 * keeps SDKEvent at the public surface for example-app parity with Swift.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.GenerationEvent
import ai.runanywhere.proto.v1.GenerationEventKind
import ai.runanywhere.proto.v1.SDKEvent
import ai.runanywhere.proto.v1.VLMStreamEvent
import ai.runanywhere.proto.v1.VLMStreamEventKind
import com.runanywhere.sdk.foundation.errors.SDKException

internal object VlmStreamEventMapper {
    fun decodeStreamPayload(bytes: ByteArray): VLMStreamEvent? =
        try {
            VLMStreamEvent.ADAPTER.decode(bytes)
        } catch (_: Exception) {
            null
        }

    /**
     * @return mapped SDK event, or null when the native event should be ignored
     * @throws SDKException on terminal ERROR events
     */
    fun toSdkEvent(event: VLMStreamEvent): SDKEvent? {
        return when (event.kind) {
            VLMStreamEventKind.VLM_STREAM_EVENT_KIND_TOKEN -> {
                val token = event.token
                if (token.isEmpty()) {
                    null
                } else {
                    val kind =
                        if (event.token_index <= 0) {
                            GenerationEventKind.GENERATION_EVENT_KIND_FIRST_TOKEN_GENERATED
                        } else {
                            GenerationEventKind.GENERATION_EVENT_KIND_TOKEN_GENERATED
                        }
                    SDKEvent(
                        generation =
                            GenerationEvent(
                                kind = kind,
                                token = token,
                            ),
                    )
                }
            }
            VLMStreamEventKind.VLM_STREAM_EVENT_KIND_COMPLETED -> {
                val text = event.result?.text.orEmpty()
                SDKEvent(
                    generation =
                        GenerationEvent(
                            kind = GenerationEventKind.GENERATION_EVENT_KIND_STREAM_COMPLETED,
                            response = text,
                            streaming_text = text,
                            tokens_count = event.result?.completion_tokens ?: 0,
                        ),
                )
            }
            VLMStreamEventKind.VLM_STREAM_EVENT_KIND_ERROR -> {
                val message = event.error_message?.takeIf { it.isNotBlank() } ?: "VLM stream failed"
                throw SDKException.vlm(message)
            }
            VLMStreamEventKind.VLM_STREAM_EVENT_KIND_STARTED,
            VLMStreamEventKind.VLM_STREAM_EVENT_KIND_IMAGE_ENCODED,
            VLMStreamEventKind.VLM_STREAM_EVENT_KIND_UNSPECIFIED,
            -> null
        }
    }

    fun shouldContinueNativeStream(event: VLMStreamEvent): Boolean =
        when (event.kind) {
            VLMStreamEventKind.VLM_STREAM_EVENT_KIND_COMPLETED,
            VLMStreamEventKind.VLM_STREAM_EVENT_KIND_ERROR,
            -> false
            else -> !event.is_final
        }
}
