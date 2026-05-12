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
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RAVoiceAgentComponentStates
import com.runanywhere.sdk.public.types.RAVoiceAgentComposeConfig
import com.squareup.wire.Message
import com.squareup.wire.ProtoAdapter
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.atomic.AtomicLong

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
    private val handleRef = AtomicLong(INVALID_HANDLE)
    private val mutex = Mutex()

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
    @Synchronized
    fun getRawHandle(): Long {
        val existing = handleRef.get()
        if (existing != INVALID_HANDLE) return existing

        val newHandle = RunAnywhereBridge.racVoiceAgentCreateStandalone()
        if (newHandle == INVALID_HANDLE) {
            throw IllegalStateException(
                "rac_voice_agent_create_standalone returned 0 — " +
                    "likely OOM or missing rac_commons linkage.",
            )
        }
        handleRef.set(newHandle)
        logger.info("Voice agent handle created: $newHandle")
        return newHandle
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
    suspend fun getHandle(): Long = mutex.withLock {
        val existing = handleRef.get()
        if (existing != INVALID_HANDLE) return@withLock existing

        // Mirror Swift CppBridge+VoiceAgent: pull a handle from each
        // sub-component actor.
        val llmHandle = CppBridgeLLM.getHandle()
        val sttHandle = CppBridgeSTT.getHandle()
        val ttsHandle = CppBridgeTTS.getHandle()
        val vadHandle = CppBridgeVAD.getHandle()
        logger.debug(
            "Composing voice agent over sub-handles: " +
                "llm=$llmHandle, stt=$sttHandle, tts=$ttsHandle, vad=$vadHandle",
        )

        val newHandle = RunAnywhereBridge.racVoiceAgentCreate(
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

        handleRef.set(newHandle)
        logger.info("Voice agent composed: $newHandle")
        newHandle
    }

    /** True when a voice-agent handle exists AND the C layer reports ready. */
    fun isReady(): Boolean {
        val handle = handleRef.get()
        if (handle == INVALID_HANDLE) return false
        return RunAnywhereBridge.racVoiceAgentIsReady(handle)
    }

    /**
     * Cleanup the voice agent — releases owned child components but keeps
     * the handle alive. Mirrors Swift `CppBridge.VoiceAgent.cleanup()`.
     *
     * No-op when no handle has been allocated.
     */
    suspend fun cleanup() = mutex.withLock {
        val handle = handleRef.get()
        if (handle == INVALID_HANDLE) return@withLock
        val result = RunAnywhereBridge.racVoiceAgentCleanup(handle)
        if (result != 0) {
            logger.warn("rac_voice_agent_cleanup returned $result for handle $handle")
        } else {
            logger.info("Voice agent cleaned up: $handle")
        }
    }

    /**
     * Release the handle + its owned component handles. Safe to call
     * multiple times; subsequent getHandle() calls re-allocate.
     */
    @Synchronized
    fun destroy() {
        val existing = handleRef.getAndSet(INVALID_HANDLE)
        if (existing != INVALID_HANDLE) {
            RunAnywhereBridge.racVoiceAgentDestroy(existing)
            logger.info("Voice agent handle destroyed: $existing")
        }
    }

    fun initialize(handle: Long, config: RAVoiceAgentComposeConfig): RAVoiceAgentComponentStates =
        decodeOrThrow(
            VoiceAgentComponentStates.ADAPTER,
            RunAnywhereBridge.racVoiceAgentInitializeProto(
                handle,
                VoiceAgentComposeConfig.ADAPTER.encode(config),
            ),
            "racVoiceAgentInitializeProto",
        )

    fun states(handle: Long): RAVoiceAgentComponentStates =
        decodeOrThrow(
            VoiceAgentComponentStates.ADAPTER,
            RunAnywhereBridge.racVoiceAgentComponentStatesProto(handle),
            "racVoiceAgentComponentStatesProto",
        )

    /**
     * Process one voice turn end-to-end (VAD → STT → LLM → TTS) over the
     * composite voice-agent handle. Mirrors Swift's
     * `CppBridge.VoiceAgent.processVoiceTurnProto(_:)` which wraps
     * `rac_voice_agent_process_voice_turn_proto`.
     *
     * The handle is resolved via [getHandle], composing the underlying LLM /
     * STT / TTS / VAD sub-handles on first call.
     *
     * @param audioBytes raw audio data for the turn (PCM16 mono unless the
     *   component is configured otherwise).
     * @return the canonical [VoiceAgentResult] proto carrying transcript,
     *   response text, synthesized audio, and per-stage timings.
     * @throws SDKException when the C ABI returns null or decoding fails.
     */
    suspend fun processVoiceTurnProto(audioBytes: ByteArray): VoiceAgentResult {
        val handle = getHandle()
        return decodeOrThrow(
            VoiceAgentResult.ADAPTER,
            RunAnywhereBridge.racVoiceAgentProcessVoiceTurnProto(handle, audioBytes),
            "racVoiceAgentProcessVoiceTurnProto",
        )
    }
}
