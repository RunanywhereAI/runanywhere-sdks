/*
 * Copyright 2024 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for VoiceAgent operations.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVoiceAgent
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

// Session state
@Volatile
private var voiceSessionActive: Boolean = false

@Volatile
private var currentSystemPrompt: String? = null

actual suspend fun RunAnywhere.configureVoiceAgent(configuration: VoiceAgentConfiguration) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    // Map public configuration to CppBridge configuration
    val bridgeConfig = CppBridgeVoiceAgent.VoiceAgentConfig(
        sttModelId = configuration.sttModelId,
        llmModelId = configuration.llmModelId,
        ttsModelPath = null,
        voiceId = configuration.ttsVoice,
        sampleRate = configuration.vadSampleRate,
        silenceTimeoutMs = (configuration.vadFrameLength * 1000).toLong(),
        enableVad = true,
        enableStreaming = true
    )

    val result = CppBridgeVoiceAgent.shared.initialize(bridgeConfig)
    if (result != 0) {
        throw SDKError.voiceAgent("Failed to configure voice agent (error: $result)")
    }
}

actual suspend fun RunAnywhere.voiceAgentComponentStates(): VoiceAgentComponentStates {
    val states = CppBridgeVoiceAgent.shared.getComponentStates()

    return VoiceAgentComponentStates(
        stt = mapComponentState(states["stt"]),
        llm = mapComponentState(states["llm"]),
        tts = mapComponentState(states["tts"])
    )
}

actual suspend fun RunAnywhere.isVoiceAgentReady(): Boolean {
    return CppBridgeVoiceAgent.shared.isReady
}

actual suspend fun RunAnywhere.processVoice(audioData: ByteArray): VoiceAgentResult {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    if (!CppBridgeVoiceAgent.shared.isReady) {
        return VoiceAgentResult(
            speechDetected = false,
            transcription = null,
            response = "Voice agent not ready",
            synthesizedAudio = null
        )
    }

    return try {
        val turnResult = CppBridgeVoiceAgent.shared.processVoiceTurn(audioData)
        VoiceAgentResult(
            speechDetected = turnResult.userText != null,
            transcription = turnResult.userText,
            response = turnResult.assistantText,
            synthesizedAudio = turnResult.audioData
        )
    } catch (e: SDKError) {
        VoiceAgentResult(
            speechDetected = false,
            transcription = null,
            response = e.message,
            synthesizedAudio = null
        )
    }
}

actual fun RunAnywhere.startVoiceSession(config: VoiceSessionConfig): Flow<VoiceSessionEvent> = flow {
    if (!isInitialized) {
        emit(VoiceSessionEvent.Error("SDK not initialized"))
        return@flow
    }

    if (!CppBridgeVoiceAgent.shared.isReady) {
        emit(VoiceSessionEvent.Error("Voice agent not ready"))
        return@flow
    }

    voiceSessionActive = true
    emit(VoiceSessionEvent.Started)

    // Set up streaming callbacks
    CppBridgeVoiceAgent.shared.responseStreamCallback = CppBridgeVoiceAgent.ResponseStreamCallback { token, isFinal ->
        // Tokens are handled by the listener
        !isFinal && voiceSessionActive
    }

    CppBridgeVoiceAgent.shared.audioStreamCallback = CppBridgeVoiceAgent.AudioStreamCallback { audioChunk, isFinal ->
        // Audio chunks are handled by the listener
        !isFinal && voiceSessionActive
    }

    // The actual voice session loop would be driven by audio input
    // This flow represents session events
}

actual suspend fun RunAnywhere.stopVoiceSession() {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    voiceSessionActive = false
    CppBridgeVoiceAgent.shared.cancel()
    CppBridgeVoiceAgent.shared.responseStreamCallback = null
    CppBridgeVoiceAgent.shared.audioStreamCallback = null
}

actual suspend fun RunAnywhere.isVoiceSessionActive(): Boolean {
    return voiceSessionActive && CppBridgeVoiceAgent.shared.isProcessing
}

actual suspend fun RunAnywhere.clearVoiceConversation() {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    CppBridgeVoiceAgent.shared.reset()
}

actual suspend fun RunAnywhere.setVoiceSystemPrompt(prompt: String) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    currentSystemPrompt = prompt
    // Re-initialize with updated prompt if agent is ready
    if (CppBridgeVoiceAgent.shared.isAgentInitialized) {
        val config = CppBridgeVoiceAgent.VoiceAgentConfig(
            systemPrompt = prompt
        )
        CppBridgeVoiceAgent.shared.initialize(config)
    }
}

// Helper to map component state string to sealed class
private fun mapComponentState(state: String?): ComponentLoadState {
    return when (state?.lowercase()) {
        "not_created", "unloaded" -> ComponentLoadState.NotLoaded
        "created", "loading" -> ComponentLoadState.Loading
        "ready", "loaded" -> ComponentLoadState.Loaded(state)
        "error", "failed" -> ComponentLoadState.Error(state)
        else -> ComponentLoadState.NotLoaded
    }
}
