// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

package com.runanywhere.adapter

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * Live v2 VoiceAgent session. Events stream via `run()`. Underlying C
 * pipeline is created on first `run()` call and torn down when the Flow
 * terminates (cancel/completion/error).
 */
class VoiceSession internal constructor(
    private val config: SolutionConfig,
    private val nativeHandle: Long,
) {
    /** Emits events until the pipeline ends, cancels, or errors. */
    fun run(): Flow<VoiceEvent> = flow {
        if (nativeHandle == 0L) {
            emit(VoiceEvent.Error(
                code = RunAnywhereException.BACKEND_UNAVAILABLE,
                message = "RunAnywhere v2 native core not linked; " +
                          "see frontends/kotlin/src/main/cpp/README.md"))
            return@flow
        }
        // TODO(phase-2): JNI bridge reads proto3 VoiceEvent bytes and emits.
    }

    fun stop() {
        // TODO(phase-2): ra_pipeline_cancel(nativeHandle)
    }

    companion object {
        internal fun create(config: SolutionConfig): VoiceSession {
            // TODO(phase-2): encode SolutionConfig to proto3, call
            // ra_pipeline_create_from_solution via JNI.
            return VoiceSession(config, nativeHandle = 0L)
        }
    }
}

/** Kotlin mirror of runanywhere.v1.VoiceEvent (will be codegen'd by Wire). */
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
