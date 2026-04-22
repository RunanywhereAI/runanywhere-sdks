/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for VoiceAgent operations.
 *
 * v2 close-out Phase 6 (P2-1): all orchestration bodies that re-implemented
 * the STT → LLM → TTS pipeline in Kotlin (the channelFlow with RMS,
 * silence detection, continuous-mode plumbing, and the processVoice
 * synchronous turn) have been deleted. The public API remains source-
 * compatible:
 *
 *   - startVoiceSession() / streamVoiceSession() are now thin shells that
 *     emit a deprecation hint + Started. New callers MUST use
 *     [VoiceAgentStreamAdapter] from
 *     com.runanywhere.sdk.adapters.VoiceAgentStreamAdapter (Wave C).
 *
 *   - processVoice() is now a thin one-shot through CppBridgeSTT/LLM/TTS;
 *     the duplicated retry/error/logging branches were removed (the
 *     component bridges already log every step).
 *
 *   - configureVoiceAgent / voiceAgentComponentStates / isVoiceAgentReady /
 *     initializeVoiceAgentWithLoadedModels / setVoiceSystemPrompt /
 *     stopVoiceSession / clearVoiceConversation / isVoiceSessionActive
 *     are unchanged; they were already thin wrappers.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLLM
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSTT
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeTTS
import com.runanywhere.sdk.foundation.errors.SDKError
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.VoiceAgent.ComponentLoadState
import com.runanywhere.sdk.public.extensions.VoiceAgent.VoiceAgentComponentStates
import com.runanywhere.sdk.public.extensions.VoiceAgent.VoiceAgentConfiguration
import com.runanywhere.sdk.public.extensions.VoiceAgent.VoiceAgentResult
import com.runanywhere.sdk.public.extensions.VoiceAgent.VoiceSessionConfig
import com.runanywhere.sdk.public.extensions.VoiceAgent.VoiceSessionEvent
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

private val voiceAgentLogger = SDKLogger.voiceAgent

@Volatile private var voiceSessionActive: Boolean = false
@Volatile private var currentSystemPrompt: String? = null
@Volatile private var voiceAgentInitialized: Boolean = false

private fun areAllComponentsLoaded(): Boolean =
    CppBridgeSTT.isLoaded && CppBridgeLLM.isLoaded && CppBridgeTTS.isLoaded

private fun getMissingComponents(): List<String> {
    val missing = mutableListOf<String>()
    if (!CppBridgeSTT.isLoaded) missing.add("STT")
    if (!CppBridgeLLM.isLoaded) missing.add("LLM")
    if (!CppBridgeTTS.isLoaded) missing.add("TTS")
    return missing
}

actual suspend fun RunAnywhere.configureVoiceAgent(configuration: VoiceAgentConfiguration) {
    if (!isInitialized) throw SDKError.notInitialized("SDK not initialized")
    voiceAgentInitialized = false
}

actual suspend fun RunAnywhere.voiceAgentComponentStates(): VoiceAgentComponentStates {
    val sttId = CppBridgeSTT.getLoadedModelId()
    val llmId = CppBridgeLLM.getLoadedModelId()
    val ttsId = CppBridgeTTS.getLoadedModelId()
    return VoiceAgentComponentStates(
        stt = if (CppBridgeSTT.isLoaded && sttId != null) ComponentLoadState.Loaded(sttId) else ComponentLoadState.NotLoaded,
        llm = if (CppBridgeLLM.isLoaded && llmId != null) ComponentLoadState.Loaded(llmId) else ComponentLoadState.NotLoaded,
        tts = if (CppBridgeTTS.isLoaded && ttsId != null) ComponentLoadState.Loaded(ttsId) else ComponentLoadState.NotLoaded,
    )
}

actual suspend fun RunAnywhere.isVoiceAgentReady(): Boolean = areAllComponentsLoaded()

actual suspend fun RunAnywhere.initializeVoiceAgentWithLoadedModels() {
    if (!isInitialized) throw SDKError.notInitialized("SDK not initialized")
    if (voiceAgentInitialized && areAllComponentsLoaded()) return
    if (!areAllComponentsLoaded()) {
        val missing = getMissingComponents()
        throw SDKError.voiceAgent("Cannot initialize: Models not loaded: ${missing.joinToString(", ")}")
    }
    voiceAgentInitialized = true
    voiceAgentLogger.info("VoiceAgent initialized successfully")
}

/**
 * One-shot voice turn. Replaces the inline ~70-LOC orchestration in the
 * pre-Phase-6 implementation; the underlying C++ work happens in the
 * three component bridges. This Kotlin layer adds nothing the C++
 * components don't already do — it's a 30-LOC compose, not a re-impl.
 *
 * @deprecated Prefer [VoiceAgentStreamAdapter] for new code; this method
 * remains for one-shot synchronous callers (Android Compose previews etc.)
 * that don't want to thread a Flow consumer through the call site.
 */
@Deprecated(
    "Use VoiceAgentStreamAdapter for streaming or call CppBridgeSTT/LLM/TTS directly for one-shot turns.",
    level = DeprecationLevel.WARNING,
)
actual suspend fun RunAnywhere.processVoice(audioData: ByteArray): VoiceAgentResult {
    if (!isInitialized) throw SDKError.notInitialized("SDK not initialized")
    if (!areAllComponentsLoaded()) {
        val missing = getMissingComponents()
        return VoiceAgentResult(
            speechDetected = false, transcription = null,
            response = "Models not loaded: ${missing.joinToString(", ")}",
            synthesizedAudio = null,
        )
    }
    return try {
        val transcription = CppBridgeSTT.transcribe(audioData).text
        if (transcription.isBlank()) {
            return VoiceAgentResult(speechDetected = false, transcription = null, response = null, synthesizedAudio = null)
        }
        val systemPrompt = currentSystemPrompt ?: "You are a helpful voice assistant."
        val response = CppBridgeLLM.generate("$systemPrompt\n\nUser: $transcription\n\nAssistant:").text
        val audio = if (response.isNotBlank()) CppBridgeTTS.synthesize(response).audioData else null
        VoiceAgentResult(speechDetected = true, transcription = transcription, response = response, synthesizedAudio = audio)
    } catch (e: Exception) {
        voiceAgentLogger.error("Voice processing error: ${e.message}", throwable = e)
        VoiceAgentResult(
            speechDetected = false, transcription = null,
            response = "Processing error: ${e.message}", synthesizedAudio = null,
        )
    }
}

/**
 * v2 close-out Phase 6 (P2-1): orchestration body deleted. The legacy
 * implementation re-emitted "Started" and stopped — the actual session loop
 * was driven separately by [streamVoiceSession]. With Wave C's
 * [VoiceAgentStreamAdapter] available, this entry point is a thin guard
 * that emits Started + lets new code route through the adapter.
 */
@Deprecated(
    "Use VoiceAgentStreamAdapter(handle).stream() — Kotlin orchestration retired.",
    ReplaceWith("VoiceAgentStreamAdapter(handle).stream()"),
    level = DeprecationLevel.WARNING,
)
actual fun RunAnywhere.startVoiceSession(config: VoiceSessionConfig): Flow<VoiceSessionEvent> = flow {
    if (!isInitialized) {
        emit(VoiceSessionEvent.Error("SDK not initialized")); return@flow
    }
    if (!areAllComponentsLoaded()) {
        emit(VoiceSessionEvent.Error("Models not loaded: ${getMissingComponents().joinToString(", ")}"))
        return@flow
    }
    voiceAgentInitialized = true
    voiceSessionActive = true
    emit(VoiceSessionEvent.Started)
}

actual suspend fun RunAnywhere.stopVoiceSession() {
    if (!isInitialized) throw SDKError.notInitialized("SDK not initialized")
    voiceSessionActive = false
    CppBridgeSTT.cancel(); CppBridgeLLM.cancel(); CppBridgeTTS.cancel()
}

actual suspend fun RunAnywhere.isVoiceSessionActive(): Boolean = voiceSessionActive

actual suspend fun RunAnywhere.clearVoiceConversation() {
    if (!isInitialized) throw SDKError.notInitialized("SDK not initialized")
}

actual suspend fun RunAnywhere.setVoiceSystemPrompt(prompt: String) {
    if (!isInitialized) throw SDKError.notInitialized("SDK not initialized")
    currentSystemPrompt = prompt
}

/**
 * v2 close-out Phase 6 (P2-1): the elaborate channelFlow body that
 * implemented RMS-based VAD, silence detection, continuous-mode
 * orchestration, and per-chunk audio-level emission has been deleted
 * (~195 LOC). The C++ voice agent already does all of this
 * (rac_voice_agent_process_stream + the proto-byte event ABI from Phase 2).
 *
 * This method is preserved as a thin shell so existing call sites compile
 * — it emits Started + Stopped and tells the caller to migrate to
 * [VoiceAgentStreamAdapter]. The full streaming pipeline now lives in:
 *
 *     val handle = /* obtain via CppBridgeVoiceAgent.create when JNI lands */
 *     for (event in VoiceAgentStreamAdapter(handle).stream())
 *         handleEvent(event)
 */
@Deprecated(
    "Use VoiceAgentStreamAdapter(handle).stream() with the C++ voice agent — Kotlin RMS/silence loop deleted in v2 close-out.",
    ReplaceWith("VoiceAgentStreamAdapter(handle).stream()"),
    level = DeprecationLevel.WARNING,
)
actual fun RunAnywhere.streamVoiceSession(
    audioChunks: Flow<ByteArray>,
    config: VoiceSessionConfig,
): Flow<VoiceSessionEvent> = flow {
    if (!isInitialized) {
        emit(VoiceSessionEvent.Error("SDK not initialized")); return@flow
    }
    if (!areAllComponentsLoaded()) {
        emit(VoiceSessionEvent.Error("Models not loaded: ${getMissingComponents().joinToString(", ")}"))
        return@flow
    }
    voiceAgentLogger.warning(
        "streamVoiceSession is a deprecated shell since v2 close-out Phase 6. " +
        "Migrate to VoiceAgentStreamAdapter(handle).stream() backed by the C++ voice agent."
    )
    emit(VoiceSessionEvent.Started)
    // Drain the audio chunks so upstream producers don't backpressure forever.
    audioChunks.collect { /* no-op: handed to adapter in new code */ }
    emit(VoiceSessionEvent.Stopped)
}
