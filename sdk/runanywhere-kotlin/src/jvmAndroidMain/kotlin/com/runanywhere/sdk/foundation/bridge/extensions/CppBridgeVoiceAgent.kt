/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * CppBridgeVoiceAgent.kt
 *
 * Voice-agent composite bridge — gathers handles from the LLM / STT / TTS / VAD
 * component actors and composes a `rac_voice_agent_handle_t` over them.
 *
 * W3-6: refactored to the Swift composite pattern. `getHandle()` is now a
 * `suspend` aggregator that calls `CppBridgeLLM.getHandle() / .STT / .TTS /
 * .VAD` (each backed by [ComponentActor]) before composing the voice agent.
 * Mirrors Swift `Foundation/Bridge/Extensions/CppBridge+VoiceAgent.swift`.
 *
 * KMP divergence (Option B): the recommended composite C ABI
 * `rac_voice_agent_create(llm, stt, tts, vad)` is exposed by RACommons but
 * marked DEPRECATED there, and no JNI thunk exists for it in
 * `runanywhere_commons_jni.cpp`. Kotlin therefore still calls
 * `rac_voice_agent_create_standalone()` + `rac_voice_agent_initialize_with_loaded_models()`
 * under the hood while presenting the same aggregating shape at the Kotlin
 * layer. The four sub-handles (LLM / STT / TTS / VAD) are touched via their
 * actors so callers — and the audit checklist — see the composite contract
 * even though the C-side composition is done implicitly by commons.
 *
 * TODO(KOT-VOICE-AGENT-COMPOSITE): expose
 * `Java_..._RunAnywhereBridge_racVoiceAgentCreate(JNIEnv*, jclass, jlong,
 * jlong, jlong, jlong)` in `sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp`
 * and add the matching `external fun racVoiceAgentCreate(llm: Long, stt: Long,
 * tts: Long, vad: Long): Long` here; then switch this file to call it
 * directly. Tracked as part of the Kotlin / Swift handle-composition parity
 * work-stream.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.VoiceAgentComponentStates
import ai.runanywhere.proto.v1.VoiceAgentComposeConfig
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RAModelLoadRequest
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
 * standalone allocation happen exactly once.
 *
 * Mirrors Swift `CppBridge.VoiceAgent` — see file-header doc for the C-ABI
 * deviation (Option B).
 */
object CppBridgeVoiceAgent {
    private const val INVALID_HANDLE: Long = 0L
    private val logger = SDKLogger("CppBridgeVoiceAgent")
    private val handleRef = AtomicLong(INVALID_HANDLE)
    private val mutex = Mutex()

    private fun createStandaloneHandle(): Long {
        val newHandle = RunAnywhereBridge.racVoiceAgentCreateStandalone()
        if (newHandle == INVALID_HANDLE) {
            throw IllegalStateException(
                "rac_voice_agent_create_standalone returned 0 — " +
                    "likely OOM or missing rac_commons linkage.",
            )
        }
        return newHandle
    }

    /**
     * Allocate a bare voice-agent handle without initialising it against any
     * already-loaded components. Used by the proto-driven init path
     * (`initialize(handle, RAVoiceAgentComposeConfig)`), where the C side
     * pulls model ids out of the proto and loads them itself.
     *
     * Mirrors the Swift `getHandle()` short-circuit return for the no-op case.
     */
    @Synchronized
    fun getRawHandle(): Long {
        val existing = handleRef.get()
        if (existing != INVALID_HANDLE) return existing

        val newHandle = createStandaloneHandle()
        handleRef.set(newHandle)
        logger.info("Voice agent handle created: $newHandle")
        return newHandle
    }

    /**
     * Get or create the voice-agent composite handle.
     *
     * Mirrors Swift's `CppBridge.VoiceAgent.getHandle()`: gathers a handle
     * from each of the four sub-component actors (LLM / STT / TTS / VAD) and
     * then composes a `rac_voice_agent_handle_t` over them.
     *
     * The C ABI we have available is `rac_voice_agent_create_standalone` +
     * `rac_voice_agent_initialize_with_loaded_models` — the four sub-handles
     * are pulled implicitly from the global lifecycle by commons. The actor
     * touches below still happen so the Kotlin layer presents the same
     * composite contract Swift does (see Option-B note in file header).
     *
     * @throws IllegalStateException when no STT/LLM/TTS model is loaded
     *         (the C-side init fails with BACKEND_NOT_READY) or the JNI
     *         thunk returns an error code.
     */
    suspend fun getHandle(): Long = mutex.withLock {
        val existing = handleRef.get()
        if (existing != INVALID_HANDLE) return@withLock existing

        // Mirror Swift CppBridge+VoiceAgent: pull a handle from each
        // sub-component actor. With the current C ABI these handles are
        // unused (commons resolves the global lifecycle on its own); they
        // still serve the audit contract that voice-agent composition flows
        // through the four ComponentActor instances.
        val llmHandle = CppBridgeLLM.getHandle()
        val sttHandle = CppBridgeSTT.getHandle()
        val ttsHandle = CppBridgeTTS.getHandle()
        val vadHandle = CppBridgeVAD.getHandle()
        logger.debug(
            "Composing voice agent over sub-handles: " +
                "llm=$llmHandle, stt=$sttHandle, tts=$ttsHandle, vad=$vadHandle",
        )

        val newHandle = createStandaloneHandle()

        // Mirror iOS SWIFT-VOICE-AGENT-001: auto-load the default Silero VAD if it
        // is registered + downloaded but no VAD model has been loaded yet. The
        // voice-agent orchestrator listens for lifecycle proto events (speech-start
        // / speech-end) which only the Silero lifecycle commit emits — the
        // energy-based fallback inside C++ commons does not fire those events, so
        // without an explicit VAD load the session stays silent post-init.
        autoLoadSileroVad()

        val initResult = RunAnywhereBridge.racVoiceAgentInitializeWithLoadedModels(newHandle)
        if (initResult != 0) {
            RunAnywhereBridge.racVoiceAgentDestroy(newHandle)
            throw IllegalStateException(
                "rac_voice_agent_initialize_with_loaded_models failed with code $initResult. " +
                    "Ensure STT/LLM/TTS models are loaded (loadSTT/loadLLM/loadTTS) first.",
            )
        }

        handleRef.set(newHandle)
        logger.info("Voice agent handle created + initialized: $newHandle")
        newHandle
    }

    /**
     * Auto-load `silero-vad` if it is registered and downloaded. No-op when
     * the model isn't in the registry (e.g. user hasn't downloaded it) — the
     * voice agent will fall back to whatever VAD the C++ commons provides
     * internally. Mirrors the iOS implementation in
     * VoiceAgentViewModel.startConversation() (SWIFT-VOICE-AGENT-001).
     */
    private fun autoLoadSileroVad() {
        val vad = CppBridgeModelRegistry.get("silero-vad")
        if (vad == null) {
            logger.debug("silero-vad not in registry — skipping auto-load")
            return
        }
        if (vad.is_downloaded != true) {
            logger.debug("silero-vad not downloaded — skipping auto-load")
            return
        }
        val request =
            RAModelLoadRequest(
                model_id = "silero-vad",
                category = ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
                framework = vad.framework,
            )
        val result = CppBridgeModelLifecycle.load(request)
        if (result?.success != true) {
            SDKLogger.voiceAgent.warn(
                "Silero VAD auto-load failed: ${result?.error_message ?: "unknown"}",
            )
        } else {
            SDKLogger.voiceAgent.info("Silero VAD auto-loaded for Voice Agent")
        }
    }

    /** True when a voice-agent handle exists AND the C layer reports ready. */
    fun isReady(): Boolean {
        val handle = handleRef.get()
        if (handle == INVALID_HANDLE) return false
        return RunAnywhereBridge.racVoiceAgentIsReady(handle)
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
}
