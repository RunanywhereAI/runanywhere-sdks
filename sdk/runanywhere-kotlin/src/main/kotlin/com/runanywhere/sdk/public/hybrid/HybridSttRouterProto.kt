/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Protobuf marshalling for the STT hybrid router JNI ABI. Pairs with
 * rac_stt_hybrid_router_jni.cpp which decodes/encodes the same
 * runanywhere.v1.* messages on the C++ side using the protobuf-generated
 * types under sdk/runanywhere-commons/src/generated/proto/hybrid_router.pb.h.
 *
 * Descriptor + policy marshalling are reused from HybridRouterProto (they
 * are capability-agnostic); STT-specific request + response shapes live
 * here.
 */

package com.runanywhere.sdk.public.hybrid

import ai.runanywhere.proto.v1.HybridRoutingContext
import ai.runanywhere.proto.v1.HybridSttTranscribeOptions
import ai.runanywhere.proto.v1.HybridSttTranscribeRequest
import ai.runanywhere.proto.v1.HybridSttTranscribeResponse
import okio.ByteString.Companion.toByteString

internal object HybridSttRouterProto {

    /**
     * Build a HybridSttTranscribeRequest carrying the audio bytes, the
     * per-request routing context, and the transcription options.
     *
     * Device-state fields live behind the cross-SDK
     * `rac_hybrid_device_state` C ABI vtable. HybridRoutingContext currently
     * carries no fields; it remains in the wire shape so future per-call
     * hints can be added without changing every caller.
     *
     * @param audioBytes  File-encoded audio (wav/mp3/flac/...) OR raw PCM.
     * @param language    Optional BCP-47 hint. Empty = let the backend auto-detect.
     * @param sampleRate  Hint for raw PCM; 0 means "engine default" (16000).
     * @param audioFormat rac_audio_format_enum_t value (0=PCM, 1=WAV, 2=MP3, ...).
     *                    0 leaves the format unspecified.
     */
    fun request(
        audioBytes: ByteArray,
        language: String = "",
        sampleRate: Int = 0,
        audioFormat: Int = 0,
    ): ByteArray {
        val context = HybridRoutingContext()
        val options = HybridSttTranscribeOptions(
            language = language,
            sample_rate = sampleRate,
            audio_format = audioFormat,
        )
        val msg = HybridSttTranscribeRequest(
            audio_bytes = audioBytes.toByteString(),
            context = context,
            options = options,
        )
        return HybridSttTranscribeRequest.ADAPTER.encode(msg)
    }

    /**
     * Decode a HybridSttTranscribeResponse returned by the JNI transcribe
     * thunk into the public [TranscribeResult] shape.
     */
    fun parseResponse(bytes: ByteArray): TranscribeResult {
        val msg = HybridSttTranscribeResponse.ADAPTER.decode(bytes)
        val routing = msg.routing
        return TranscribeResult(
            text = msg.text,
            detectedLanguage = msg.detected_language,
            routing = RoutedMetadata(
                chosenModelId = routing?.chosen_model_id.orEmpty(),
                wasFallback = routing?.was_fallback ?: false,
                attemptCount = routing?.attempt_count ?: 0,
                primaryErrorCode = routing?.primary_error_code ?: 0,
                primaryErrorMessage = routing?.primary_error_message.orEmpty(),
                confidence = routing?.confidence ?: Float.NaN,
                primaryConfidence = routing?.primary_confidence ?: Float.NaN,
            ),
        )
    }
}
