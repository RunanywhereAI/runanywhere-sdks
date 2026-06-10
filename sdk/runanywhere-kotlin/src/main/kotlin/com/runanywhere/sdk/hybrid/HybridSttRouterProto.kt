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

package com.runanywhere.sdk.hybrid

import ai.runanywhere.proto.v1.HybridRoutingContext
import ai.runanywhere.proto.v1.HybridSttTranscribeRequest
import ai.runanywhere.proto.v1.HybridSttTranscribeResponse
import com.runanywhere.sdk.foundation.errors.SDKException
import okio.ByteString.Companion.toByteString
import ai.runanywhere.proto.v1.ErrorCode as ProtoErrorCode

internal object HybridSttRouterProto {
    /**
     * Build a HybridSttTranscribeRequest carrying the audio bytes, an
     * (empty, present) routing context, and the transcription options.
     *
     * HybridRoutingContext currently has no fields — device-state lives
     * behind the `rac_hybrid_device_state` vtable. The empty message is still
     * set explicitly so the wire shape (field 2 present) is stable for future
     * per-call hints, matching the C++/Swift peers.
     */
    fun request(
        audio: ByteArray,
        options: HybridTranscribeOptions,
    ): ByteArray {
        val msg =
            HybridSttTranscribeRequest(
                audio_bytes = audio.toByteString(),
                context = HybridRoutingContext(),
                options = options,
            )
        return HybridSttTranscribeRequest.ADAPTER.encode(msg)
    }

    /**
     * Decode a HybridSttTranscribeResponse returned by the JNI transcribe
     * thunk into the public [HybridTranscribeResult], raising the native rc
     * as an [SDKException] when non-zero (mirrors Swift's decodeResponse).
     */
    fun parseResponse(bytes: ByteArray): HybridTranscribeResult {
        val msg = HybridSttTranscribeResponse.ADAPTER.decode(bytes)
        if (msg.rc != 0) {
            throw SDKException.make(
                code = ProtoErrorCode.ERROR_CODE_SERVICE_NOT_AVAILABLE,
                message = msg.error_msg.ifEmpty { "Hybrid STT transcribe failed (rc=${msg.rc})" },
            )
        }
        return HybridTranscribeResult(
            text = msg.text,
            detectedLanguage = msg.detected_language,
            routing = msg.routing ?: HybridRoutedMetadata(),
        )
    }
}
