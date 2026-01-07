/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for VoiceAgent operations.
 *
 * Note: This implementation orchestrates STT, LLM, and TTS at the Kotlin level
 * since the native VoiceAgent C++ component is not yet implemented.
 */

package com.runanywhere.sdk.public.extensions

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

// Session state managed at Kotlin level
@Volatile
private var voiceSessionActive: Boolean = false

@Volatile
private var currentSystemPrompt: String? = null

@Volatile
private var voiceAgentInitialized: Boolean = false

/**
 * Check if all required components (STT, LLM, TTS) are loaded.
 * This is the Kotlin-level "readiness" check since native VoiceAgent isn't available.
 */
private fun areAllComponentsLoaded(): Boolean {
    return CppBridgeSTT.isLoaded && CppBridgeLLM.isLoaded && CppBridgeTTS.isLoaded
}

/**
 * Get list of missing components for error messages.
 */
private fun getMissingComponents(): List<String> {
    val missing = mutableListOf<String>()
    if (!CppBridgeSTT.isLoaded) missing.add("STT")
    if (!CppBridgeLLM.isLoaded) missing.add("LLM")
    if (!CppBridgeTTS.isLoaded) missing.add("TTS")
    return missing
}

actual suspend fun RunAnywhere.configureVoiceAgent(configuration: VoiceAgentConfiguration) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    // Configuration stored - model IDs can be used to load models if needed
    // The systemPrompt is set separately via setVoiceSystemPrompt()
    // Actual initialization happens when all models are loaded
    voiceAgentInitialized = false
}

actual suspend fun RunAnywhere.voiceAgentComponentStates(): VoiceAgentComponentStates {
    // Query individual component bridges directly for accurate state and model IDs
    // This mirrors iOS's approach of querying CppBridge.STT.shared.isLoaded and currentModelId separately

    val sttLoaded = CppBridgeSTT.isLoaded
    val sttModelId = CppBridgeSTT.getLoadedModelId()

    val llmLoaded = CppBridgeLLM.isLoaded
    val llmModelId = CppBridgeLLM.getLoadedModelId()

    val ttsLoaded = CppBridgeTTS.isLoaded
    val ttsVoiceId = CppBridgeTTS.getLoadedModelId()

    return VoiceAgentComponentStates(
        stt = if (sttLoaded && sttModelId != null) ComponentLoadState.Loaded(sttModelId) else ComponentLoadState.NotLoaded,
        llm = if (llmLoaded && llmModelId != null) ComponentLoadState.Loaded(llmModelId) else ComponentLoadState.NotLoaded,
        tts = if (ttsLoaded && ttsVoiceId != null) ComponentLoadState.Loaded(ttsVoiceId) else ComponentLoadState.NotLoaded
    )
}

actual suspend fun RunAnywhere.isVoiceAgentReady(): Boolean {
    // VoiceAgent is "ready" when all three components are loaded
    // Since native VoiceAgent doesn't exist, we track readiness based on component states
    return areAllComponentsLoaded()
}

actual suspend fun RunAnywhere.initializeVoiceAgentWithLoadedModels() {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    // Already initialized and all components loaded
    if (voiceAgentInitialized && areAllComponentsLoaded()) {
        return
    }

    // Check if all component models are loaded
    if (!areAllComponentsLoaded()) {
        val missing = getMissingComponents()
        throw SDKError.voiceAgent("Cannot initialize: Models not loaded: ${missing.joinToString(", ")}")
    }

    // All components are loaded - mark voice agent as initialized at Kotlin level
    voiceAgentInitialized = true
}

actual suspend fun RunAnywhere.processVoice(audioData: ByteArray): VoiceAgentResult {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    // Check if all components are loaded
    if (!areAllComponentsLoaded()) {
        val missing = getMissingComponents()
        return VoiceAgentResult(
            speechDetected = false,
            transcription = null,
            response = "Models not loaded: ${missing.joinToString(", ")}",
            synthesizedAudio = null
        )
    }

    return try {
        // Step 1: Transcribe audio using STT
        val transcriptionResult = CppBridgeSTT.transcribe(audioData)
        val transcriptionText = transcriptionResult.text
        if (transcriptionText.isBlank()) {
            return VoiceAgentResult(
                speechDetected = false,
                transcription = null,
                response = null,
                synthesizedAudio = null
            )
        }

        // Step 2: Generate response using LLM
        // Format as a chat prompt with system message and user input
        val systemPrompt = currentSystemPrompt ?: "You are a helpful voice assistant."
        val chatPrompt = "$systemPrompt\n\nUser: $transcriptionText\n\nAssistant:"
        val generationResult = CppBridgeLLM.generate(chatPrompt)
        val responseText = generationResult.text

        // Step 3: Synthesize speech using TTS
        val audioOutput = if (responseText.isNotBlank()) {
            val synthesisResult = CppBridgeTTS.synthesize(responseText)
            synthesisResult.audioData
        } else {
            null
        }

        VoiceAgentResult(
            speechDetected = true,
            transcription = transcriptionText,
            response = responseText,
            synthesizedAudio = audioOutput
        )
    } catch (e: Exception) {
        VoiceAgentResult(
            speechDetected = false,
            transcription = null,
            response = "Processing error: ${e.message}",
            synthesizedAudio = null
        )
    }
}

actual fun RunAnywhere.startVoiceSession(config: VoiceSessionConfig): Flow<VoiceSessionEvent> = flow {
    if (!isInitialized) {
        emit(VoiceSessionEvent.Error("SDK not initialized"))
        return@flow
    }

    // Check if all component models are loaded
    if (!areAllComponentsLoaded()) {
        val missing = getMissingComponents()
        emit(VoiceSessionEvent.Error("Models not loaded: ${missing.joinToString(", ")}"))
        return@flow
    }

    // Mark voice agent as initialized and session as active
    voiceAgentInitialized = true
    voiceSessionActive = true
    emit(VoiceSessionEvent.Started)

    // The actual voice session loop would be driven by audio input from the app layer
    // This flow represents session events that the app can collect
    // Audio recording and processing should be handled by the app using processVoice()
}

actual suspend fun RunAnywhere.stopVoiceSession() {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    voiceSessionActive = false
    // Cancel any ongoing operations
    CppBridgeSTT.cancel()
    CppBridgeLLM.cancel()
    CppBridgeTTS.cancel()
}

actual suspend fun RunAnywhere.isVoiceSessionActive(): Boolean {
    return voiceSessionActive
}

actual suspend fun RunAnywhere.clearVoiceConversation() {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    // Clear conversation context - for LLM, this would clear any stored conversation history
    // Currently no persistent conversation state, so this is a no-op
}

actual suspend fun RunAnywhere.setVoiceSystemPrompt(prompt: String) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    currentSystemPrompt = prompt
}
