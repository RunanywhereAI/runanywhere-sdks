package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.features.voiceagent.VoiceAgentCapability
import com.runanywhere.sdk.features.voiceagent.VoiceAgentComponentStates
import com.runanywhere.sdk.features.voiceagent.AudioPipelineState
import com.runanywhere.sdk.features.voiceagent.VoiceAgentConfiguration
import com.runanywhere.sdk.features.voiceagent.VoiceAgentResult
import com.runanywhere.sdk.features.voiceagent.VoiceAgentEvent
import com.runanywhere.sdk.features.voiceagent.VoiceAgentPipelineState
import com.runanywhere.sdk.data.models.SDKError
import kotlinx.coroutines.flow.Flow

// ═══════════════════════════════════════════════════════════════════════════
// RunAnywhere VoiceAgent Extensions
// End-to-end voice AI pipeline operations aligned with iOS RunAnywhere+VoiceAgent.swift
// ═══════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Component State Management
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Get the current state of all Voice Agent sub-components
 * Useful for displaying loading progress in UI
 *
 * @return VoiceAgentComponentStates with individual component states
 */
fun RunAnywhere.getVoiceAgentComponentStates(): VoiceAgentComponentStates {
    requireInitialized()

    val capability = voiceAgentCapability
        ?: throw SDKError.ComponentNotInitialized("Voice Agent capability not available")

    return capability.getComponentStates()
}

/**
 * Check if all Voice Agent components (STT, LLM, TTS) are ready
 */
val RunAnywhere.areAllVoiceComponentsReady: Boolean
    get() = voiceAgentCapability?.areAllComponentsReady ?: false

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Initialization
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Initialize Voice Agent with full configuration
 * Matches iOS initializeVoiceAgent(_ config: VoiceAgentConfiguration)
 *
 * @param config VoiceAgentConfiguration with all sub-component configs
 * @throws SDKError if initialization fails
 */
suspend fun RunAnywhere.initializeVoiceAgent(config: VoiceAgentConfiguration) {
    requireInitialized()
    ensureServicesReady()

    val capability = voiceAgentCapability
        ?: throw SDKError.ComponentNotInitialized("Voice Agent capability not available")

    capability.initialize(config)
}

/**
 * Initialize Voice Agent with specific model IDs
 * Matches iOS initializeVoiceAgent(sttModelId:llmModelId:ttsVoice:)
 *
 * @param sttModelId STT model ID (empty string = use already loaded)
 * @param llmModelId LLM model ID (empty string = use already loaded)
 * @param ttsVoice TTS voice ID (empty string = use already loaded)
 * @throws SDKError if initialization fails
 */
suspend fun RunAnywhere.initializeVoiceAgent(
    sttModelId: String,
    llmModelId: String,
    ttsVoice: String = ""
) {
    requireInitialized()
    ensureServicesReady()

    val capability = voiceAgentCapability
        ?: throw SDKError.ComponentNotInitialized("Voice Agent capability not available")

    capability.initialize(sttModelId, llmModelId, ttsVoice)
}

/**
 * Initialize Voice Agent with already-loaded models
 * Matches iOS initializeVoiceAgentWithLoadedModels()
 *
 * Uses whatever models are already loaded in STT, LLM, and TTS capabilities
 *
 * @throws SDKError if initialization fails or required models not loaded
 */
suspend fun RunAnywhere.initializeVoiceAgentWithLoadedModels() {
    requireInitialized()
    ensureServicesReady()

    val capability = voiceAgentCapability
        ?: throw SDKError.ComponentNotInitialized("Voice Agent capability not available")

    capability.initializeWithLoadedModels()
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Status
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Check if Voice Agent is fully initialized and ready for use
 */
val RunAnywhere.isVoiceAgentReady: Boolean
    get() = voiceAgentCapability?.isReady ?: false

/**
 * Get current Voice Agent pipeline state
 */
val RunAnywhere.voiceAgentPipelineState: VoiceAgentPipelineState
    get() = voiceAgentCapability?.pipelineState ?: VoiceAgentPipelineState.IDLE

/**
 * Check if Voice Agent is currently processing audio
 */
val RunAnywhere.isVoiceAgentProcessing: Boolean
    get() = voiceAgentCapability?.isProcessing ?: false

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Voice Processing
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Process a complete voice turn through the full VAD -> STT -> LLM -> TTS pipeline
 * Matches iOS processVoiceTurn(_ audioData: Data) -> VoiceAgentResult
 *
 * @param audioData Raw audio data (PCM format expected)
 * @return VoiceAgentResult with transcription, response, and synthesized audio
 * @throws SDKError if processing fails
 */
suspend fun RunAnywhere.processVoiceTurn(audioData: ByteArray): VoiceAgentResult {
    requireInitialized()

    val capability = voiceAgentCapability
        ?: throw SDKError.ComponentNotReady("Voice Agent not available. Call initializeVoiceAgent() first.")

    return capability.processVoiceTurn(audioData)
}

/**
 * Process a stream of audio through the Voice Agent pipeline
 * Matches iOS processVoiceStream(_ audioStream: AsyncStream<Data>) -> AsyncThrowingStream<VoiceAgentEvent, Error>
 *
 * @param audioStream Flow of audio data chunks
 * @return Flow of VoiceAgentEvent for reactive consumption
 */
fun RunAnywhere.processVoiceStream(audioStream: Flow<ByteArray>): Flow<VoiceAgentEvent> {
    requireInitialized()

    val capability = voiceAgentCapability
        ?: throw SDKError.ComponentNotReady("Voice Agent not available. Call initializeVoiceAgent() first.")

    return capability.processStream(audioStream)
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Individual Operations
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Transcribe audio using the Voice Agent's STT
 * Matches iOS voiceAgentTranscribe(_ audioData: Data) -> String
 *
 * @param audioData Raw audio data
 * @return Transcribed text
 */
suspend fun RunAnywhere.voiceAgentTranscribe(audioData: ByteArray): String {
    requireInitialized()

    val capability = voiceAgentCapability
        ?: throw SDKError.ComponentNotReady("Voice Agent not available. Call initializeVoiceAgent() first.")

    return capability.transcribe(audioData)
}

/**
 * Generate response using the Voice Agent's LLM
 * Matches iOS voiceAgentGenerateResponse(_ prompt: String) -> String
 *
 * @param prompt Text prompt
 * @return Generated response
 */
suspend fun RunAnywhere.voiceAgentGenerateResponse(prompt: String): String {
    requireInitialized()

    val capability = voiceAgentCapability
        ?: throw SDKError.ComponentNotReady("Voice Agent not available. Call initializeVoiceAgent() first.")

    return capability.generateResponse(prompt)
}

/**
 * Synthesize speech using the Voice Agent's TTS
 * Matches iOS voiceAgentSynthesizeSpeech(_ text: String) -> Data
 *
 * @param text Text to synthesize
 * @return Synthesized audio data
 */
suspend fun RunAnywhere.voiceAgentSynthesizeSpeech(text: String): ByteArray {
    requireInitialized()

    val capability = voiceAgentCapability
        ?: throw SDKError.ComponentNotReady("Voice Agent not available. Call initializeVoiceAgent() first.")

    return capability.synthesizeSpeech(text)
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Cleanup
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Cleanup Voice Agent and release all resources
 */
suspend fun RunAnywhere.cleanupVoiceAgent() {
    voiceAgentCapability?.cleanup()
}
