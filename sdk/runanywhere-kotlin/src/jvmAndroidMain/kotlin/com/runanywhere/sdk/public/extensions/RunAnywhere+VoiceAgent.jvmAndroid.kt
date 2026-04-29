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

import ai.runanywhere.proto.v1.AudioFormat
import ai.runanywhere.proto.v1.ComponentLoadState
import ai.runanywhere.proto.v1.STTOutput
import ai.runanywhere.proto.v1.TTSOutput
import ai.runanywhere.proto.v1.TTSSynthesisMetadata
import ai.runanywhere.proto.v1.TranscriptionMetadata
import ai.runanywhere.proto.v1.VoiceAgentComponentStates
import ai.runanywhere.proto.v1.VoiceAgentConfig
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLLM
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSTT
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeTTS
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import okio.ByteString.Companion.toByteString
// v3.1: VoiceAgentResult / VoiceSessionConfig / VoiceSessionEvent /
// Flow / flow imports removed — the actual declarations using them
// (processVoice / startVoiceSession / streamVoiceSession) were deleted.

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

actual suspend fun RunAnywhere.initializeVoiceAgent(config: VoiceAgentConfig) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    voiceAgentInitialized = false
    // Store config intent; actual model loading is caller's responsibility
    // before calling initializeVoiceAgentWithLoadedModels().
    voiceAgentLogger.info("Voice agent configured with VoiceAgentConfig: llm=${config.llm_model_id}, stt=${config.stt_model_id}, tts=${config.tts_model_id}")
}

actual suspend fun RunAnywhere.getVoiceAgentComponentStates(): VoiceAgentComponentStates {
    fun toProtoState(isLoaded: Boolean): ComponentLoadState =
        if (isLoaded) {
            ComponentLoadState.COMPONENT_LOAD_STATE_LOADED
        } else {
            ComponentLoadState.COMPONENT_LOAD_STATE_NOT_LOADED
        }
    val sttState = toProtoState(CppBridgeSTT.isLoaded)
    val llmState = toProtoState(CppBridgeLLM.isLoaded)
    val ttsState = toProtoState(CppBridgeTTS.isLoaded)
    val allLoaded = CppBridgeSTT.isLoaded && CppBridgeLLM.isLoaded && CppBridgeTTS.isLoaded
    val anyLoading = false // No async loading state tracked at this layer
    return VoiceAgentComponentStates(
        stt_state = sttState,
        llm_state = llmState,
        tts_state = ttsState,
        vad_state = ComponentLoadState.COMPONENT_LOAD_STATE_NOT_LOADED,
        ready = allLoaded,
        any_loading = anyLoading,
    )
}

actual suspend fun RunAnywhere.isVoiceAgentReady(): Boolean = areAllComponentsLoaded()

actual suspend fun RunAnywhere.initializeVoiceAgentWithLoadedModels() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    if (voiceAgentInitialized && areAllComponentsLoaded()) return
    if (!areAllComponentsLoaded()) {
        val missing = getMissingComponents()
        throw SDKException.voiceAgent("Cannot initialize: Models not loaded: ${missing.joinToString(", ")}")
    }
    voiceAgentInitialized = true
    voiceAgentLogger.info("VoiceAgent initialized successfully")
}

// v3.1: processVoice / startVoiceSession / streamVoiceSession DELETED.
// Use CppBridgeVoiceAgent.getHandle() + VoiceAgentStreamAdapter(handle)
// for streaming, or compose CppBridgeSTT/LLM/TTS directly for one-shot
// turns (see Android sample's processVoiceTurnDirect helper).

actual suspend fun RunAnywhere.stopVoiceSession() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    voiceSessionActive = false
    CppBridgeSTT.cancel()
    CppBridgeLLM.cancel()
    CppBridgeTTS.cancel()
}

actual suspend fun RunAnywhere.isVoiceSessionActive(): Boolean = voiceSessionActive

actual suspend fun RunAnywhere.clearVoiceConversation() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
}

actual suspend fun RunAnywhere.setVoiceSystemPrompt(prompt: String) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    currentSystemPrompt = prompt
}

// ─────────────────────────────────────────────────────────────────────────────
// Phase 4a — VoiceAgent processing parity actuals.
//
// One-shot composition of CppBridgeSTT/LLM/TTS, mirroring Swift's
// `RunAnywhere+VoiceAgent.swift`. The streaming path remains via
// `VoiceAgentStreamAdapter`.
// ─────────────────────────────────────────────────────────────────────────────

actual suspend fun RunAnywhere.processVoiceTurn(
    audioData: ByteArray,
): com.runanywhere.sdk.public.extensions.VoiceAgent.VoiceAgentResult {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    if (!areAllComponentsLoaded()) {
        val missing = getMissingComponents().joinToString(", ")
        throw SDKException.voiceAgent("Voice agent not ready: missing components: $missing")
    }

    val sttOutput = voiceAgentTranscribe(audioData)
    val transcription = sttOutput.text
    val response = voiceAgentGenerateResponse(transcription)
    val ttsOutput = voiceAgentSynthesizeSpeech(response)
    val audio = ttsOutput.audio_data.toByteArray()

    return com.runanywhere.sdk.public.extensions.VoiceAgent.VoiceAgentResult(
        speechDetected = transcription.isNotBlank(),
        transcription = transcription.takeIf { it.isNotBlank() },
        response = response.takeIf { it.isNotBlank() },
        synthesizedAudio = audio.takeIf { it.isNotEmpty() },
    )
}

actual suspend fun RunAnywhere.voiceAgentTranscribe(audioData: ByteArray): STTOutput {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    val result = CppBridgeSTT.transcribe(audioData)
    val audioLengthSec = audioData.size.toDouble() / 2.0 / 16000.0
    return STTOutput(
        text = result.text,
        confidence = result.confidence,
        metadata =
            TranscriptionMetadata(
                model_id = CppBridgeSTT.getLoadedModelId() ?: "unknown",
                processing_time_ms = result.processingTimeMs,
                audio_length_ms = (audioLengthSec * 1000).toLong(),
            ),
    )
}

actual suspend fun RunAnywhere.voiceAgentGenerateResponse(prompt: String): String {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    val systemPrompt = currentSystemPrompt
    val cfg =
        if (systemPrompt != null) {
            CppBridgeLLM.GenerationConfig(systemPrompt = systemPrompt)
        } else {
            CppBridgeLLM.GenerationConfig.DEFAULT
        }
    val result = CppBridgeLLM.generate(prompt, cfg)
    return result.text
}

actual suspend fun RunAnywhere.voiceAgentSynthesizeSpeech(text: String): TTSOutput {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    val result = CppBridgeTTS.synthesize(text)
    val voiceId = CppBridgeTTS.getLoadedModelId() ?: "unknown"
    return TTSOutput(
        audio_data = result.audioData.toByteString(),
        audio_format = AudioFormat.AUDIO_FORMAT_PCM,
        sample_rate = 22050,
        duration_ms = result.durationMs,
        metadata =
            TTSSynthesisMetadata(
                voice_id = voiceId,
                processing_time_ms = result.processingTimeMs,
                character_count = text.length,
                audio_duration_ms = result.durationMs,
            ),
    )
}

actual suspend fun RunAnywhere.cleanupVoiceAgent() {
    // Match Swift: cleanup voice-agent handle + reset flag.
    voiceAgentInitialized = false
    voiceSessionActive = false
    com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVoiceAgent
        .destroy()
}

// ─────────────────────────────────────────────────────────────────────────────
// Round 1 KOTLIN (Task 7 / G-E4): public streamVoiceAgent() entry-point.
// Replaces the pattern: CppBridgeVoiceAgent.getHandle() + VoiceAgentStreamAdapter(handle)
// that leaked CppBridge internals into example apps.
// ─────────────────────────────────────────────────────────────────────────────

actual fun RunAnywhere.streamVoiceAgent(): kotlinx.coroutines.flow.Flow<ai.runanywhere.proto.v1.VoiceEvent> {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    val handle =
        com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVoiceAgent
            .getHandle()
    return com.runanywhere.sdk.adapters
        .VoiceAgentStreamAdapter(handle)
        .stream()
}
