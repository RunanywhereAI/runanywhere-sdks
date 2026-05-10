/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.STTOptions
import ai.runanywhere.proto.v1.STTOutput
import ai.runanywhere.proto.v1.STTStreamEvent
import com.runanywhere.sdk.foundation.bridge.CppBridge
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.NativeProtoProgressListener
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RASTTOptions
import com.runanywhere.sdk.public.types.RATranscriptionResult
import com.squareup.wire.Message
import com.squareup.wire.ProtoAdapter

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

private fun checkRc(rc: Int, operation: String) {
    if (rc != RunAnywhereBridge.RAC_SUCCESS) {
        throw SDKException.operation("$operation failed with rc=$rc")
    }
}

/**
 * Mirrors Swift CppBridge+STT.swift. Wraps `rac_stt_*_proto` C ABI.
 */
object CppBridgeSTT {
    @Volatile
    private var handle: Long = 0L

    private val lock = Any()

    @Throws(SDKException::class)
    fun getHandle(): Long {
        synchronized(lock) {
            if (handle == 0L) create()
            if (handle == 0L) {
                throw SDKException.notInitialized("STT component not created")
            }
            return handle
        }
    }

    fun create(): Int {
        synchronized(lock) {
            if (handle != 0L) return 0
            if (!CppBridge.isNativeLibraryLoaded) {
                throw SDKException.notInitialized(
                    "Native library not available. Please ensure the native libraries are bundled in your APK.",
                )
            }
            val result =
                try {
                    RunAnywhereBridge.racSttComponentCreate()
                } catch (e: UnsatisfiedLinkError) {
                    throw SDKException.notInitialized(
                        "STT native library not available: ${e.message}",
                    )
                }
            if (result == 0L) return -1
            handle = result
            return 0
        }
    }

    fun destroy() {
        synchronized(lock) {
            if (handle == 0L) return
            RunAnywhereBridge.racSttComponentDestroy(handle)
            handle = 0L
        }
    }

    fun transcribe(audioData: ByteArray, options: RASTTOptions): RATranscriptionResult {
        create()
        return decodeOrThrow(
            STTOutput.ADAPTER,
            RunAnywhereBridge.racSttComponentTranscribeProto(
                getHandle(),
                audioData,
                STTOptions.ADAPTER.encode(options),
            ),
            "racSttComponentTranscribeProto",
        )
    }

    fun transcribeStream(
        audioData: ByteArray,
        options: RASTTOptions,
        onEvent: (STTStreamEvent) -> Boolean,
    ) {
        create()
        // Native emits canonical STTStreamEvent envelopes (STARTED / PARTIAL /
        // FINAL / ERROR with monotonically-increasing seq and timestamp_us).
        // Kotlin simply decodes and forwards.
        val rc =
            RunAnywhereBridge.racSttComponentTranscribeStreamProto(
                getHandle(),
                audioData,
                STTOptions.ADAPTER.encode(options),
                NativeProtoProgressListener { bytes ->
                    onEvent(STTStreamEvent.ADAPTER.decode(bytes))
                },
            )
        checkRc(rc, "racSttComponentTranscribeStreamProto")
    }
}
