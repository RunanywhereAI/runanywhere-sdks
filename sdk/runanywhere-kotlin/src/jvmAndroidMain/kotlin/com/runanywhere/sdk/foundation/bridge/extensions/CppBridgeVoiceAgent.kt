/*
 * CppBridgeVoiceAgent.kt
 *
 * v3.1 P3.2: Kotlin facade over the voice-agent handle lifecycle JNI
 * thunks (rac_voice_agent_create_standalone, initialize_with_loaded_models,
 * is_ready, destroy). Mirrors Swift's CppBridge.VoiceAgent pattern.
 *
 * The facade maintains a single lazily-created handle that is bound to
 * the currently-loaded STT/LLM/TTS models (via
 * rac_voice_agent_initialize_with_loaded_models). Callers feed this
 * handle to VoiceAgentStreamAdapter(handle) to subscribe to the proto
 * event stream.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import java.util.concurrent.atomic.AtomicLong

/**
 * Voice-agent handle lifecycle facade. Thread-safe; uses atomic handle
 * refs so concurrent getHandle() calls converge on a single native
 * allocation.
 */
object CppBridgeVoiceAgent {
    private const val INVALID_HANDLE: Long = 0L
    private val logger = SDKLogger("CppBridgeVoiceAgent")
    private val handleRef = AtomicLong(INVALID_HANDLE)

    /**
     * Get or create a voice-agent handle. Lazy; the first call allocates
     * a native voice-agent via rac_voice_agent_create_standalone and
     * initializes it against already-loaded STT/LLM/TTS singletons.
     *
     * @return native handle (Long); 0 on failure.
     * @throws IllegalStateException when no STT/LLM/TTS model is loaded
     *         (the C-side init fails with BACKEND_NOT_READY) or the JNI
     *         thunk returns an error code.
     */
    @Synchronized
    fun getHandle(): Long {
        val existing = handleRef.get()
        if (existing != INVALID_HANDLE) return existing

        val newHandle = RunAnywhereBridge.racVoiceAgentCreateStandalone()
        if (newHandle == INVALID_HANDLE) {
            throw IllegalStateException(
                "rac_voice_agent_create_standalone returned 0 — " +
                    "likely OOM or missing rac_commons linkage.",
            )
        }

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
        return newHandle
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
}
