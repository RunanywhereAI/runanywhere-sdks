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
        tts = if (ttsLoaded && ttsVoiceId != null) ComponentLoadState.Loaded(ttsVoiceId) else ComponentLoadState.NotLoaded,
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
        voiceAgentLogger.debug("VoiceAgent already initialized")
        return
    }

    voiceAgentLogger.info("Initializing VoiceAgent with loaded models...")

    // Check if all component models are loaded
    if (!areAllComponentsLoaded()) {
        val missing = getMissingComponents()
        voiceAgentLogger.error("Cannot initialize: Models not loaded: ${missing.joinToString(", ")}")
        throw SDKError.voiceAgent("Cannot initialize: Models not loaded: ${missing.joinToString(", ")}")
    }

    // All components are loaded - mark voice agent as initialized at Kotlin level
    voiceAgentInitialized = true
    voiceAgentLogger.info("VoiceAgent initialized successfully")
}

actual suspend fun RunAnywhere.processVoice(audioData: ByteArray): VoiceAgentResult {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    voiceAgentLogger.debug("Processing voice input: ${audioData.size} bytes")

    // Check if all components are loaded
    if (!areAllComponentsLoaded()) {
        val missing = getMissingComponents()
        voiceAgentLogger.warning("Models not loaded: ${missing.joinToString(", ")}")
        return VoiceAgentResult(
            speechDetected = false,
            transcription = null,
            response = "Models not loaded: ${missing.joinToString(", ")}",
            synthesizedAudio = null,
        )
    }

    return try {
        // Step 1: Transcribe audio using STT
        voiceAgentLogger.debug("Step 1: Transcribing audio...")
        val transcriptionResult = CppBridgeSTT.transcribe(audioData)
        val transcriptionText = transcriptionResult.text
        if (transcriptionText.isBlank()) {
            voiceAgentLogger.debug("No speech detected in audio")
            return VoiceAgentResult(
                speechDetected = false,
                transcription = null,
                response = null,
                synthesizedAudio = null,
            )
        }
        voiceAgentLogger.info("Transcription: ${transcriptionText.take(100)}${if (transcriptionText.length > 100) "..." else ""}")

        // Step 2: Generate response using LLM
        voiceAgentLogger.debug("Step 2: Generating LLM response...")
        val systemPrompt = currentSystemPrompt ?: "You are a helpful voice assistant."
        val chatPrompt = "$systemPrompt\n\nUser: $transcriptionText\n\nAssistant:"
        val generationResult = CppBridgeLLM.generate(chatPrompt)
        val responseText = generationResult.text
        voiceAgentLogger.info("Response: ${responseText.take(100)}${if (responseText.length > 100) "..." else ""}")

        // Step 3: Synthesize speech using TTS
        voiceAgentLogger.debug("Step 3: Synthesizing TTS audio...")
        val audioOutput =
            if (responseText.isNotBlank()) {
                val synthesisResult = CppBridgeTTS.synthesize(responseText)
                voiceAgentLogger.debug("TTS synthesis complete: ${synthesisResult.audioData.size} bytes")
                synthesisResult.audioData
            } else {
                null
            }

        voiceAgentLogger.info("Voice processing complete")
        VoiceAgentResult(
            speechDetected = true,
            transcription = transcriptionText,
            response = responseText,
            synthesizedAudio = audioOutput,
        )
    } catch (e: Exception) {
        voiceAgentLogger.error("Voice processing error: ${e.message}", throwable = e)
        VoiceAgentResult(
            speechDetected = false,
            transcription = null,
            response = "Processing error: ${e.message}",
            synthesizedAudio = null,
        )
    }
}

actual fun RunAnywhere.startVoiceSession(config: VoiceSessionConfig): Flow<VoiceSessionEvent> =
    flow {
        if (!isInitialized) {
            voiceAgentLogger.error("Cannot start voice session: SDK not initialized")
            emit(VoiceSessionEvent.Error("SDK not initialized"))
            return@flow
        }

        // Check if all component models are loaded
        if (!areAllComponentsLoaded()) {
            val missing = getMissingComponents()
            voiceAgentLogger.error("Cannot start voice session: Models not loaded: ${missing.joinToString(", ")}")
            emit(VoiceSessionEvent.Error("Models not loaded: ${missing.joinToString(", ")}"))
            return@flow
        }

        // Mark voice agent as initialized and session as active
        voiceAgentInitialized = true
        voiceSessionActive = true
        voiceAgentLogger.info("Voice session started")
        emit(VoiceSessionEvent.Started)

        // The actual voice session loop would be driven by audio input from the app layer
        // This flow represents session events that the app can collect
        // Audio recording and processing should be handled by the app using processVoice()
    }

actual suspend fun RunAnywhere.stopVoiceSession() {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    voiceAgentLogger.info("Stopping voice session...")
    voiceSessionActive = false
    // Cancel any ongoing operations
    CppBridgeSTT.cancel()
    CppBridgeLLM.cancel()
    CppBridgeTTS.cancel()
    voiceAgentLogger.info("Voice session stopped")
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
