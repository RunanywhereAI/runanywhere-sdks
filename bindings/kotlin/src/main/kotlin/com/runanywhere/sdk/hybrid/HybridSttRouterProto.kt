/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Protobuf marshalling for the STT hybrid router JNI ABI. Pairs with
 * rac_stt_hybrid_router_jni.cpp which decodes/encodes the same
 * runanywhere.v1.* messages on the C++ side using the protobuf-generated
 * types under core/src/generated/proto/hybrid_router.pb.h.
 *
 * Descriptor + policy marshalling are reused from HybridRouterProto (they
 * are capability-agnostic); STT-specific request + response shapes live
 * here.
 */

package com.runanywhere.sdk.hybrid

import ai.runanywhere.proto.v1.HybridSttTranscribeRequest
import ai.runanywhere.proto.v1.HybridSttTranscribeResponse
import com.runanywhere.sdk.foundation.errors.SDKException
import okio.ByteString.Companion.toByteString
import ai.runanywhere.proto.v1.ErrorCode as ProtoErrorCode

internal object HybridSttRouterProto {
    /**
     * Build a HybridSttTranscribeRequest carrying the audio bytes and the
     * transcription options.
     *
     * `HybridRoutingContext`/`HybridSttTranscribeRequest.context` are
     * deleted outright (idl/hybrid_router.proto); device-state still lives
     * entirely behind the `rac_hybrid_device_state` vtable, so there is no
     * per-call context left to set. Mirrors Swift's `encodeRequest`.
     */
    fun request(
        audio: ByteArray,
        options: HybridTranscribeOptions,
    ): ByteArray {
        val msg =
            HybridSttTranscribeRequest(
                audio_bytes = audio.toByteString(),
                options = options,
            )
        return HybridSttTranscribeRequest.ADAPTER.encode(msg)
    }

    /**
     * Decode a HybridSttTranscribeResponse returned by the JNI transcribe
     * thunk into the public [HybridTranscribeResult], raising the native rc
     * as an [SDKException] when non-zero (mirrors Swift's decodeResponse).
     *
     * `error_msg` is deleted outright (idl/hybrid_router.proto): the
     * response now carries only the bare `rc` on failure, with no
     * human-readable message field.
     */
    fun parseResponse(bytes: ByteArray): HybridTranscribeResult {
        val msg = HybridSttTranscribeResponse.ADAPTER.decode(bytes)
        if (msg.rc != 0) {
            throw SDKException.make(
                code = ProtoErrorCode.ERROR_CODE_SERVICE_NOT_AVAILABLE,
                message = "Hybrid STT transcribe failed (rc=${msg.rc})",
            )
        }
        return HybridTranscribeResult(
            text = msg.text,
            detectedLanguage = msg.detected_language,
            routing = msg.routing ?: HybridRoutedMetadata(),
        )
    }
}
