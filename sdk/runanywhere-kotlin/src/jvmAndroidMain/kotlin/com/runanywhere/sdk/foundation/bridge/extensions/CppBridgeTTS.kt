/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.TTSOptions
import ai.runanywhere.proto.v1.TTSOutput
import ai.runanywhere.proto.v1.TTSVoiceInfo
import com.runanywhere.sdk.foundation.bridge.CppBridge
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.NativeProtoProgressListener
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
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
 * Mirrors Swift CppBridge+TTS.swift. Wraps `rac_tts_*_proto` C ABI.
 */
object CppBridgeTTS {
    @Volatile
    private var handle: Long = 0L

    private val lock = Any()

    @Throws(SDKException::class)
    fun getHandle(): Long {
        synchronized(lock) {
            if (handle == 0L) create()
            if (handle == 0L) {
                throw SDKException.notInitialized("TTS component not created")
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
                    RunAnywhereBridge.racTtsComponentCreate()
                } catch (e: UnsatisfiedLinkError) {
                    throw SDKException.notInitialized(
                        "TTS native library not available: ${e.message}",
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
            RunAnywhereBridge.racTtsComponentDestroy(handle)
            handle = 0L
        }
    }

    fun voices(): List<TTSVoiceInfo> {
        create()
        val voices = mutableListOf<TTSVoiceInfo>()
        val rc =
            RunAnywhereBridge.racTtsComponentListVoicesProto(
                getHandle(),
                NativeProtoProgressListener { bytes ->
                    voices += TTSVoiceInfo.ADAPTER.decode(bytes)
                    true
                },
            )
        checkRc(rc, "racTtsComponentListVoicesProto")
        return voices
    }

    fun synthesize(text: String, options: TTSOptions): TTSOutput {
        create()
        return decodeOrThrow(
            TTSOutput.ADAPTER,
            RunAnywhereBridge.racTtsComponentSynthesizeProto(
                getHandle(),
                text,
                TTSOptions.ADAPTER.encode(options),
            ),
            "racTtsComponentSynthesizeProto",
        )
    }

    fun synthesizeStream(
        text: String,
        options: TTSOptions,
        onChunk: (TTSOutput) -> Boolean,
    ) {
        create()
        val rc =
            RunAnywhereBridge.racTtsComponentSynthesizeStreamProto(
                getHandle(),
                text,
                TTSOptions.ADAPTER.encode(options),
                NativeProtoProgressListener { bytes ->
                    onChunk(TTSOutput.ADAPTER.decode(bytes))
                },
            )
        checkRc(rc, "racTtsComponentSynthesizeStreamProto")
    }
}
