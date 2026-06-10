/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * CppBridgeVoiceAgent.kt
 *
 * Voice-agent composite bridge — gathers handles from the LLM / STT / TTS / VAD
 * component actors and composes a `rac_voice_agent_handle_t` over them via
 * the composite `rac_voice_agent_create(llm, stt, tts, vad)` C ABI.
 *
 * Mirrors Swift `Foundation/Bridge/Extensions/CppBridge+VoiceAgent.swift`
 * one-for-one: `getHandle()` gathers four sub-component handles and calls the
 * composite constructor, `cleanup()` releases owned child components without
 * destroying the handle, and `destroy()` cleans then frees.
 *
 * The proto-driven init path (`initializeVoiceAgent(config)`) still has its
 * own dedicated entry point [getRawHandle], which allocates a bare standalone
 * handle without requiring the four sub-components to be loaded — the C side
 * pulls model ids out of the `VoiceAgentComposeConfig` proto and loads them
 * itself. That path is logically distinct from the composite-with-loaded-
 * models flow and is preserved.
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
 * Voice-agent composite facade. Thread-safe; a coroutine [Mutex] serializes
 * concurrent composite-handle creation so the four sub-handle gathers and the
 * composite allocation happen exactly once.
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
     * Allocate a bare voice-agent handle without initialising it against any
     * already-loaded components. Used by the proto-driven init path
     * (`initialize(handle, RAVoiceAgentComposeConfig)`), where the C side
     * pulls model ids out of the proto and loads them itself.
     *
     * Distinct from [getHandle] — that path requires LLM / STT / TTS / VAD
     * to already be loaded and composes a handle over them via
     * `rac_voice_agent_create(...)`.
     */
    suspend fun getRawHandle(): Long =
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

    /**
     * Get or create the voice-agent composite handle.
     *
     * Mirrors Swift's `CppBridge.VoiceAgent.getHandle()` one-for-one:
     * gathers a handle from each of the four sub-component actors
     * (LLM / STT / TTS / VAD) and then composes a `rac_voice_agent_handle_t`
     * over them via the composite `rac_voice_agent_create(llm, stt, tts, vad)`
     * C ABI.
     *
     * @throws SDKException when any sub-component handle fails to allocate,
     *         or when the composite-create JNI thunk returns 0 (which the
     *         C side maps to `rac_voice_agent_create` failing — typically
     *         because one of the sub-handles is invalid).
     */
    suspend fun getHandle(): Long {
        // Sub-component actors take their own mutexes, so we must NOT hold
        // this mutex while awaiting them or we risk an A→B/B→A deadlock with
        // a concurrent cleanup() that already holds this mutex and tries to
        // re-enter an LLM/STT/TTS/VAD actor.
        val llmHandle = CppBridgeLLM.getHandle()
        val sttHandle = CppBridgeSTT.getHandle()
        val ttsHandle = CppBridgeTTS.getHandle()
        val vadHandle = CppBridgeVAD.getHandle()

        return mutex.withLock {
            val existing = handle
            if (existing != INVALID_HANDLE) return@withLock existing

            logger.debug(
                "Composing voice agent over sub-handles: " +
                    "llm=$llmHandle, stt=$sttHandle, tts=$ttsHandle, vad=$vadHandle",
            )

            val newHandle =
                RunAnywhereBridge.racVoiceAgentCreate(
                    llmHandle,
                    sttHandle,
                    ttsHandle,
                    vadHandle,
                )
            if (newHandle == INVALID_HANDLE) {
                throw SDKException.voiceAgent(
                    "rac_voice_agent_create returned 0 — failed to compose voice agent " +
                        "over sub-handles (llm=$llmHandle, stt=$sttHandle, tts=$ttsHandle, " +
                        "vad=$vadHandle).",
                )
            }

            handle = newHandle
            logger.info("Voice agent composed: $newHandle")
            newHandle
        }
    }

    /** True when a voice-agent handle exists AND the C layer reports ready. */
    fun isReady(): Boolean {
        val h = handle
        if (h == INVALID_HANDLE) return false
        return RunAnywhereBridge.racVoiceAgentIsReady(h)
    }

    /**
     * Cleanup the voice agent — releases owned child components but keeps
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
     * composite voice-agent handle. Mirrors Swift's
     * `CppBridge.VoiceAgent.processVoiceTurnProto(_:)` which wraps
     * `rac_voice_agent_process_voice_turn_proto`.
     *
     * The handle is resolved via [getHandle], composing the underlying LLM /
     * STT / TTS / VAD sub-handles on first call. The native call runs under
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
