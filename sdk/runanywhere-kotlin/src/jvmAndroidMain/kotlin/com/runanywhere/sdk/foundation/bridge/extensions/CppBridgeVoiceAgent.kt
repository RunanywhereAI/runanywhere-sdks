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

import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelLoadRequest
import ai.runanywhere.proto.v1.VoiceAgentComponentStates
import ai.runanywhere.proto.v1.VoiceAgentComposeConfig
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.squareup.wire.Message
import com.squareup.wire.ProtoAdapter
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
 * Voice-agent handle lifecycle facade. Thread-safe; uses atomic handle
 * refs so concurrent getHandle() calls converge on a single native
 * allocation.
 */
object CppBridgeVoiceAgent {
    private const val INVALID_HANDLE: Long = 0L
    private val logger = SDKLogger("CppBridgeVoiceAgent")
    private val handleRef = AtomicLong(INVALID_HANDLE)

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
        return newHandle
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
            ModelLoadRequest(
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

    fun initialize(handle: Long, config: VoiceAgentComposeConfig): VoiceAgentComponentStates =
        decodeOrThrow(
            VoiceAgentComponentStates.ADAPTER,
            RunAnywhereBridge.racVoiceAgentInitializeProto(
                handle,
                VoiceAgentComposeConfig.ADAPTER.encode(config),
            ),
            "racVoiceAgentInitializeProto",
        )

    fun states(handle: Long): VoiceAgentComponentStates =
        decodeOrThrow(
            VoiceAgentComponentStates.ADAPTER,
            RunAnywhereBridge.racVoiceAgentComponentStatesProto(handle),
            "racVoiceAgentComponentStatesProto",
        )
}
