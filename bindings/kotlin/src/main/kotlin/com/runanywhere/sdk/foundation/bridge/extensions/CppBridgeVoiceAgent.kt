/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * CppBridgeVoiceAgent.kt
 *
 * Voice-agent bridge — owns one standalone `rac_voice_agent_handle_t` whose
 * child components are managed by commons.
 *
 * Both proto-driven initialization and the loaded-model flow use the same
 * handle. Proto operations resolve models through the canonical commons
 * lifecycle store rather than borrowing platform component handles.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.VoiceAgentComponentStates
import ai.runanywhere.proto.v1.VoiceAgentComposeConfig
import ai.runanywhere.proto.v1.VoiceAgentResult
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RAVoiceAgentComponentStates
import com.runanywhere.sdk.public.types.RAVoiceAgentComposeConfig
import com.squareup.wire.Message
import com.squareup.wire.ProtoAdapter
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

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

/**
 * Voice-agent facade. Thread-safe; a coroutine [Mutex] serializes concurrent
 * handle creation so allocation happens exactly once.
 *
 * Mirrors Swift `CppBridge.VoiceAgent`.
 */
object CppBridgeVoiceAgent {
    private const val INVALID_HANDLE: Long = 0L
    private val logger = SDKLogger("CppBridgeVoiceAgent")

    /**
     * Single coroutine [Mutex] guards both the stored handle slot AND the
     * lifetime of in-flight native operations. All public APIs are suspend
     * and serialize through this mutex so destroy() cannot interleave with
     * an in-flight processVoiceTurnProto/getHandle/cleanup/initialize call.
     *
     * Mirrors Swift's `CppBridge.VoiceAgent` actor isolation — there, the
     * compiler enforces that destroy() waits for the in-flight native call
     * to finish before freeing the underlying rac_voice_agent_handle_t.
     */
    private val mutex = Mutex()

    /** Reads outside the lock are best-effort snapshots for non-state APIs. */
    @Volatile
    private var handle: Long = INVALID_HANDLE

    /**
     * Get or create the standalone voice-agent handle.
     */
    suspend fun getHandle(): Long =
        mutex.withLock {
            val existing = handle
            if (existing != INVALID_HANDLE) return@withLock existing

            val newHandle = RunAnywhereBridge.racVoiceAgentCreateStandalone()
            if (newHandle == INVALID_HANDLE) {
                throw IllegalStateException(
                    "rac_voice_agent_create_standalone returned 0 — " +
                        "likely OOM or missing rac_commons linkage.",
                )
            }

            handle = newHandle
            logger.info("Voice agent handle created: $newHandle")
            newHandle
        }

    /** True when a voice-agent handle exists AND the C layer reports ready. */
    fun isReady(): Boolean {
        val h = handle
        if (h == INVALID_HANDLE) return false
        return RunAnywhereBridge.racVoiceAgentIsReady(h)
    }

    /**
     * Cleanup the voice agent — resets its child components but keeps
     * the handle alive. Mirrors Swift `CppBridge.VoiceAgent.cleanup()`.
     *
     * No-op when no handle has been allocated.
     */
    suspend fun cleanup() =
        mutex.withLock {
            val h = handle
            if (h == INVALID_HANDLE) return@withLock
            val result = RunAnywhereBridge.racVoiceAgentCleanup(h)
            if (result != 0) {
                logger.warn("rac_voice_agent_cleanup returned $result for handle $h")
            } else {
                logger.info("Voice agent cleaned up: $h")
            }
        }

    /**
     * Release the handle + its owned component handles. Suspends behind the
     * same [mutex] as in-flight native operations so destroy waits for the
     * current processVoiceTurnProto / getHandle / cleanup to finish before
     * freeing the C-side rac_voice_agent_handle_t. Safe to call multiple
     * times; subsequent getHandle() calls re-allocate.
     */
    suspend fun destroy() =
        mutex.withLock {
            val existing = handle
            if (existing != INVALID_HANDLE) {
                RunAnywhereBridge.racVoiceAgentDestroy(existing)
                handle = INVALID_HANDLE
                logger.info("Voice agent handle destroyed: $existing")
            }
        }

    suspend fun initialize(handle: Long, config: RAVoiceAgentComposeConfig): RAVoiceAgentComponentStates =
        mutex.withLock {
            decodeOrThrow(
                VoiceAgentComponentStates.ADAPTER,
                RunAnywhereBridge.racVoiceAgentInitializeProto(
                    handle,
                    VoiceAgentComposeConfig.ADAPTER.encode(config),
                ),
                "racVoiceAgentInitializeProto",
            )
        }

    suspend fun states(handle: Long): RAVoiceAgentComponentStates =
        mutex.withLock {
            decodeOrThrow(
                VoiceAgentComponentStates.ADAPTER,
                RunAnywhereBridge.racVoiceAgentComponentStatesProto(handle),
                "racVoiceAgentComponentStatesProto",
            )
        }

    /**
     * Process one voice turn end-to-end (VAD → STT → LLM → TTS) over the
     * voice-agent handle. Mirrors Swift's
     * `CppBridge.VoiceAgent.processVoiceTurnProto(_:)` which wraps
     * `rac_voice_agent_process_voice_turn_proto`.
     *
     * The handle is resolved via [getHandle] on first call. The native call runs under
     * the same [mutex] so destroy() cannot free the handle mid-call.
     *
     * @param audioBytes raw audio data for the turn (PCM16 mono unless the
     *   component is configured otherwise).
     * @return the canonical [VoiceAgentResult] proto carrying transcript,
     *   response text, synthesized audio, and per-stage timings.
     * @throws SDKException when the C ABI returns null or decoding fails.
     */
    suspend fun processVoiceTurnProto(audioBytes: ByteArray): VoiceAgentResult {
        // Ensure handle exists before taking the per-call lock. getHandle()
        // re-enters this mutex internally so it must run outside withLock.
        getHandle()
        return mutex.withLock {
            val h = handle
            if (h == INVALID_HANDLE) {
                throw SDKException.voiceAgent(
                    "rac_voice_agent_process_voice_turn_proto: handle destroyed before call",
                )
            }
            decodeOrThrow(
                VoiceAgentResult.ADAPTER,
                RunAnywhereBridge.racVoiceAgentProcessVoiceTurnProto(h, audioBytes),
                "racVoiceAgentProcessVoiceTurnProto",
            )
        }
    }
}
