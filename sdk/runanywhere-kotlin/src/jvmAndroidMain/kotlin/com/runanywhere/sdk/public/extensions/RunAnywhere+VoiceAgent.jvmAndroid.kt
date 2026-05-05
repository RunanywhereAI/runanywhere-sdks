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
 *   - startVoiceSession(), streamVoiceSession(), and processVoice() were
 *     deleted. Streaming callers use [VoiceAgentStreamAdapter]; one-shot
 *     callers use processVoiceTurn(VoiceAgentTurnRequest).
 *
 *   - configureVoiceAgent / voiceAgentComponentStates / isVoiceAgentReady /
 *     initializeVoiceAgentWithLoadedModels / setVoiceSystemPrompt /
 *     stopVoiceSession / clearVoiceConversation / isVoiceSessionActive
 *     are unchanged; they were already thin wrappers.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.ComponentLifecycleState
import ai.runanywhere.proto.v1.ComponentLoadState
import ai.runanywhere.proto.v1.LLMGenerationOptions
import ai.runanywhere.proto.v1.SDKComponent
import ai.runanywhere.proto.v1.STTOptions
import ai.runanywhere.proto.v1.STTOutput
import ai.runanywhere.proto.v1.TTSOptions
import ai.runanywhere.proto.v1.TTSOutput
import ai.runanywhere.proto.v1.VoiceAgentComponentStates
import ai.runanywhere.proto.v1.VoiceAgentComposeConfig
import ai.runanywhere.proto.v1.VoiceAgentConfig
import ai.runanywhere.proto.v1.VoiceAgentResult
import ai.runanywhere.proto.v1.VoiceAgentTurnRequest
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLLMProto
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelLifecycleProto
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSTTProto
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeTTSProto
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVoiceAgent
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVoiceAgentProto
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
// v3.1: VoiceSessionEvent / Flow / flow imports removed — the actual declarations using them
// (processVoice / startVoiceSession / streamVoiceSession) were deleted.

private val voiceAgentLogger = SDKLogger.voiceAgent

@Volatile private var voiceSessionActive: Boolean = false

@Volatile private var currentSystemPrompt: String? = null

@Volatile private var voiceAgentInitialized: Boolean = false

private fun isComponentReady(component: SDKComponent): Boolean =
    CppBridgeModelLifecycleProto.snapshot(component)?.let {
        it.state == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY &&
            it.model_id.isNotEmpty()
    } ?: false

private fun areAllComponentsLoaded(): Boolean =
    isComponentReady(SDKComponent.SDK_COMPONENT_STT) &&
        isComponentReady(SDKComponent.SDK_COMPONENT_LLM) &&
        isComponentReady(SDKComponent.SDK_COMPONENT_TTS)

private fun getMissingComponents(): List<String> {
    val missing = mutableListOf<String>()
    if (!isComponentReady(SDKComponent.SDK_COMPONENT_STT)) missing.add("STT")
    if (!isComponentReady(SDKComponent.SDK_COMPONENT_LLM)) missing.add("LLM")
    if (!isComponentReady(SDKComponent.SDK_COMPONENT_TTS)) missing.add("TTS")
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
// for streaming, or call processVoiceTurn(VoiceAgentTurnRequest) for the
// current native audio-only one-shot path.

actual suspend fun RunAnywhere.stopVoiceSession() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    voiceSessionActive = false
    // Cancel each component via the native cancel ABI — C++ owns the
    // cancellation flag. The legacy CppBridge{LLM,STT,TTS}.cancel
    // shims (which managed per-component Kotlin state) were deleted.
    CppBridgeLLMProto.cancel()
    com.runanywhere.sdk.native.bridge.RunAnywhereBridge.racSttComponentCancel(
        CppBridgeSTTProto.getHandle(),
    )
    com.runanywhere.sdk.native.bridge.RunAnywhereBridge.racTtsComponentCancel(
        CppBridgeTTSProto.getHandle(),
    )
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
// One-shot composition of CppBridgeSTTProto/LLMProto/TTSProto, mirroring Swift's
// `RunAnywhere+VoiceAgent.swift`. The streaming path remains via
// `VoiceAgentStreamAdapter`.
// ─────────────────────────────────────────────────────────────────────────────

actual suspend fun RunAnywhere.processVoiceTurn(
    request: VoiceAgentTurnRequest,
): VoiceAgentResult {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    if (request.audio_data.size == 0) {
        throw SDKException.invalidArgument("VoiceAgentTurnRequest.audio_data is required")
    }

    val unsupportedFields = request.unsupportedAndroidAudioOnlyFields()
    if (unsupportedFields.isNotEmpty()) {
        throw SDKException.notImplemented(
            "Native generated VoiceAgentTurnRequest ABI unavailable for fields: " +
                unsupportedFields.joinToString(", "),
        )
    }

    return CppBridgeVoiceAgentProto.processVoiceTurn(
        CppBridgeVoiceAgent.getRawHandle(),
        request.audio_data.toByteArray(),
    )
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
