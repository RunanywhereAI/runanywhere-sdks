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

// v3.1: processVoice / startVoiceSession / streamVoiceSession DELETED.
// Use CppBridgeVoiceAgent.getHandle() + VoiceAgentStreamAdapter(handle)
// for streaming, or compose CppBridgeSTT/LLM/TTS directly for one-shot
// turns (see Android sample's processVoiceTurnDirect helper).

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
    if (!isInitialized) throw SDKError.notInitialized("SDK not initialized")
    if (!areAllComponentsLoaded()) {
        val missing = getMissingComponents().joinToString(", ")
        throw SDKError.voiceAgent("Voice agent not ready: missing components: $missing")
    }

    val transcription = voiceAgentTranscribe(audioData)
    val response = voiceAgentGenerateResponse(transcription)
    val audio = voiceAgentSynthesizeSpeech(response)

    return com.runanywhere.sdk.public.extensions.VoiceAgent.VoiceAgentResult(
        speechDetected = transcription.isNotBlank(),
        transcription = transcription.takeIf { it.isNotBlank() },
        response = response.takeIf { it.isNotBlank() },
        synthesizedAudio = audio.takeIf { it.isNotEmpty() },
    )
}

actual suspend fun RunAnywhere.voiceAgentTranscribe(audioData: ByteArray): String {
    if (!isInitialized) throw SDKError.notInitialized("SDK not initialized")
    val result = CppBridgeSTT.transcribe(audioData)
    return result.text
}

actual suspend fun RunAnywhere.voiceAgentGenerateResponse(prompt: String): String {
    if (!isInitialized) throw SDKError.notInitialized("SDK not initialized")
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

actual suspend fun RunAnywhere.voiceAgentSynthesizeSpeech(text: String): ByteArray {
    if (!isInitialized) throw SDKError.notInitialized("SDK not initialized")
    val result = CppBridgeTTS.synthesize(text)
    return result.audioData
}

actual suspend fun RunAnywhere.cleanupVoiceAgent() {
    // Match Swift: cleanup voice-agent handle + reset flag.
    voiceAgentInitialized = false
    voiceSessionActive = false
    com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVoiceAgent.destroy()
}
