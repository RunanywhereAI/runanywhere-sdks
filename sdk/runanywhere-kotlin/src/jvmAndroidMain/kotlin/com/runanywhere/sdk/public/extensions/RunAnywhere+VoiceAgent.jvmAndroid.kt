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

import ai.runanywhere.proto.v1.ComponentLoadState
import ai.runanywhere.proto.v1.LLMGenerationOptions
import ai.runanywhere.proto.v1.STTOptions
import ai.runanywhere.proto.v1.STTOutput
import ai.runanywhere.proto.v1.TTSOptions
import ai.runanywhere.proto.v1.TTSOutput
import ai.runanywhere.proto.v1.VoiceAgentComponentStates
import ai.runanywhere.proto.v1.VoiceAgentComposeConfig
import ai.runanywhere.proto.v1.VoiceAgentConfig
import ai.runanywhere.proto.v1.VoiceAgentResult
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLLM
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSTT
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeTTS
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVoiceAgent
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVoiceAgentProto
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
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
    val composeConfig =
        VoiceAgentComposeConfig(
            stt_model_id = config.stt_model_id.takeIf { it.isNotBlank() },
            llm_model_id = config.llm_model_id.takeIf { it.isNotBlank() },
            tts_voice_id = config.tts_model_id.takeIf { it.isNotBlank() },
            vad_sample_rate = config.sample_rate_hz,
        )
    val states =
        CppBridgeVoiceAgentProto.initialize(
            CppBridgeVoiceAgent.getRawHandle(),
            composeConfig,
        )
    voiceAgentInitialized = states.ready
    voiceAgentLogger.info("Voice agent initialized from VoiceAgentConfig: ready=${states.ready}")
}

actual suspend fun RunAnywhere.getVoiceAgentComponentStates(): VoiceAgentComponentStates {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    return CppBridgeVoiceAgentProto.states(CppBridgeVoiceAgent.getRawHandle())
}

actual suspend fun RunAnywhere.isVoiceAgentReady(): Boolean =
    isInitialized && CppBridgeVoiceAgentProto.states(CppBridgeVoiceAgent.getRawHandle()).ready

actual suspend fun RunAnywhere.initializeVoiceAgentWithLoadedModels() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    if (voiceAgentInitialized && areAllComponentsLoaded()) return
    if (!areAllComponentsLoaded()) {
        val missing = getMissingComponents()
        throw SDKException.voiceAgent("Cannot initialize: Models not loaded: ${missing.joinToString(", ")}")
    }
    CppBridgeVoiceAgent.getHandle()
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
): VoiceAgentResult {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    return CppBridgeVoiceAgentProto.processVoiceTurn(CppBridgeVoiceAgent.getRawHandle(), audioData)
}

actual suspend fun RunAnywhere.voiceAgentTranscribe(audioData: ByteArray): STTOutput {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    return transcribeWithOptions(audioData, STTOptions())
}

actual suspend fun RunAnywhere.voiceAgentGenerateResponse(prompt: String): String {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    val result = generate(prompt, LLMGenerationOptions(system_prompt = currentSystemPrompt))
    return result.text
}

actual suspend fun RunAnywhere.voiceAgentSynthesizeSpeech(text: String): TTSOutput {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    return synthesize(text, TTSOptions())
}

actual suspend fun RunAnywhere.cleanupVoiceAgent() {
    // Match Swift: cleanup voice-agent handle + reset flag.
    voiceAgentInitialized = false
    voiceSessionActive = false
    CppBridgeVoiceAgent.destroy()
}

// ─────────────────────────────────────────────────────────────────────────────
// Round 1 KOTLIN (Task 7 / G-E4): public streamVoiceAgent() entry-point.
// Replaces the pattern: CppBridgeVoiceAgent.getHandle() + VoiceAgentStreamAdapter(handle)
// that leaked CppBridge internals into example apps.
// ─────────────────────────────────────────────────────────────────────────────

actual fun RunAnywhere.streamVoiceAgent(): kotlinx.coroutines.flow.Flow<ai.runanywhere.proto.v1.VoiceEvent> {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    val handle = CppBridgeVoiceAgent.getHandle()
    return com.runanywhere.sdk.adapters
        .VoiceAgentStreamAdapter(handle)
        .stream()
}
