// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

package com.runanywhere.adapter

import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.consumeAsFlow

/**
 * Live v2 VoiceAgent session. Events stream via `run()`. Underlying C
 * pipeline is created on first `run()` call and torn down when the Flow
 * terminates (cancel/completion/error).
 */
class VoiceSession internal constructor(private val config: SolutionConfig) {

    private var nativeHandle: Long = 0L
    private val channel = Channel<VoiceEvent>(Channel.BUFFERED)

    fun run(): Flow<VoiceEvent> {
        if (!NativeLibrary.isLoaded) {
            channel.trySend(VoiceEvent.Error(
                RunAnywhereException.BACKEND_UNAVAILABLE,
                "racommons_core native lib not on java.library.path"))
            channel.close()
            return channel.consumeAsFlow()
        }
        if (config !is VoiceAgentConfig) {
            channel.trySend(VoiceEvent.Error(
                RunAnywhereException.BACKEND_UNAVAILABLE,
                "only VoiceAgent wired through ra_pipeline yet"))
            channel.close()
            return channel.consumeAsFlow()
        }
        val emitter = Emitter(channel)
        nativeHandle = nativeCreate(
            emitter,
            config.llm, config.stt, config.tts, config.vad,
            config.sampleRateHz, config.chunkMs,
            config.enableBargeIn,
            config.systemPrompt, config.maxContextTokens, config.temperature,
            config.emitPartials, config.emitThoughts)
        if (nativeHandle == 0L) {
            channel.trySend(VoiceEvent.Error(
                RunAnywhereException.BACKEND_UNAVAILABLE,
                "ra_pipeline_create_voice_agent returned null"))
            channel.close()
        } else {
            val rc = nativeRun(nativeHandle)
            if (rc != 0) {
                channel.trySend(VoiceEvent.Error(rc,
                    "ra_pipeline_run failed: $rc"))
                channel.close()
            }
        }
        return channel.consumeAsFlow()
    }

    fun stop() {
        if (nativeHandle != 0L) nativeCancel(nativeHandle)
    }

    fun feedAudio(samples: FloatArray, sampleRateHz: Int) {
        if (nativeHandle != 0L) nativeFeedAudio(nativeHandle, samples, sampleRateHz)
    }

    fun bargeIn() {
        if (nativeHandle != 0L) nativeBargeIn(nativeHandle)
    }

    @Suppress("unused")  // called from JNI
    internal class Emitter(private val channel: Channel<VoiceEvent>) {
        fun onEvent(kind: Int, text: String, isFinal: Boolean,
                     tokenKind: Int, vadType: Int, sampleRateHz: Int) {
            val event = when (kind) {
                1 -> VoiceEvent.UserSaid(text, isFinal)
                2 -> VoiceEvent.AssistantTok(text, tokenKindOf(tokenKind), isFinal)
                3 -> VoiceEvent.Audio(ByteArray(0), sampleRateHz)  // pcm path deferred
                5 -> VoiceEvent.Interrupted(text)
                7 -> VoiceEvent.Error(-1, text)
                else -> null
            }
            event?.let { channel.trySend(it) }
        }
        fun onError(code: Int, message: String) {
            channel.trySend(VoiceEvent.Error(code, message))
        }
        fun onDone() { channel.close() }

        private fun tokenKindOf(k: Int): TokenKind = when (k) {
            2 -> TokenKind.THOUGHT
            3 -> TokenKind.TOOL_CALL
            else -> TokenKind.ANSWER
        }
    }

    // JNI entry points — implemented in frontends/kotlin/src/main/cpp/jni_bridge.cpp.
    private external fun nativeCreate(
        emitter: Emitter,
        llm: String, stt: String, tts: String, vad: String,
        sampleRate: Int, chunkMs: Int,
        enableBargeIn: Boolean,
        systemPrompt: String, maxContextTokens: Int, temperature: Float,
        emitPartials: Boolean, emitThoughts: Boolean): Long
    private external fun nativeRun(handle: Long): Int
    private external fun nativeCancel(handle: Long): Int
    private external fun nativeDestroy(handle: Long)
    private external fun nativeFeedAudio(handle: Long, samples: FloatArray,
                                          sampleRateHz: Int): Int
    private external fun nativeBargeIn(handle: Long): Int

    protected fun finalize() {
        if (nativeHandle != 0L) nativeDestroy(nativeHandle)
        nativeHandle = 0L
    }

    companion object {
        internal fun create(config: SolutionConfig): VoiceSession =
            VoiceSession(config)
    }
}

internal object NativeLibrary {
    val isLoaded: Boolean = try {
        System.loadLibrary("racommons_core")
        true
    } catch (t: UnsatisfiedLinkError) {
        false
    }
}

/** Kotlin mirror of runanywhere.v1.VoiceEvent. */
sealed interface VoiceEvent {
    data class UserSaid(val text: String, val isFinal: Boolean) : VoiceEvent
    data class AssistantTok(val text: String, val kind: TokenKind, val isFinal: Boolean) : VoiceEvent
    data class Audio(val pcm: ByteArray, val sampleRateHz: Int) : VoiceEvent {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is Audio) return false
            return sampleRateHz == other.sampleRateHz && pcm.contentEquals(other.pcm)
        }
        override fun hashCode(): Int = 31 * sampleRateHz + pcm.contentHashCode()
    }
    data class Interrupted(val reason: String) : VoiceEvent
    data class Error(val code: Int, val message: String) : VoiceEvent
}

enum class TokenKind { ANSWER, THOUGHT, TOOL_CALL }

class RunAnywhereException(code: Int, msg: String) : Exception("[$code] $msg") {
    companion object {
        const val BACKEND_UNAVAILABLE = -6
        const val CANCELLED           = -1
        const val MODEL_NOT_FOUND     = -4
    }
}
