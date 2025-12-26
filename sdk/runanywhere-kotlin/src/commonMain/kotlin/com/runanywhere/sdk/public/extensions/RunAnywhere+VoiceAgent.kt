package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.features.vad.VADConfiguration
import com.runanywhere.sdk.features.voiceagent.VoiceAgentComponentStates
import com.runanywhere.sdk.features.voiceagent.VoiceAgentConfiguration
import com.runanywhere.sdk.features.voiceagent.VoiceAgentEvent
import com.runanywhere.sdk.features.voiceagent.VoiceAgentPipelineState
import com.runanywhere.sdk.features.voiceagent.VoiceAgentResult
import com.runanywhere.sdk.features.voiceagent.VoiceSessionConfig
import com.runanywhere.sdk.features.voiceagent.VoiceSessionHandle
import com.runanywhere.sdk.public.RunAnywhere
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
    return voiceAgentCapability.getComponentStates()
}

/**
 * Check if all Voice Agent components (STT, LLM, TTS) are ready
 */
val RunAnywhere.areAllVoiceComponentsReady: Boolean
    get() = voiceAgentCapability.areAllComponentsReady

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
    voiceAgentCapability.initialize(config)
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
    ttsVoice: String = "",
) {
    requireInitialized()
    ensureServicesReady()
    voiceAgentCapability.initialize(sttModelId, llmModelId, ttsVoice)
}

/**
 * Initialize Voice Agent with already-loaded models
 * Matches iOS initializeVoiceAgentWithLoadedModels()
 *
 * Uses whatever models are already loaded in STT, LLM, and TTS capabilities
 *
 * @param vadConfig Optional VAD configuration. Defaults to VADConfiguration() which uses a balanced threshold.
 *                  Use VADConfiguration.sensitive() for whisper detection in quiet environments.
 *                  Use VADConfiguration.conservative() for noisy environments.
 * @throws SDKError if initialization fails or required models not loaded
 */
suspend fun RunAnywhere.initializeVoiceAgentWithLoadedModels(vadConfig: VADConfiguration = VADConfiguration()) {
    requireInitialized()
    ensureServicesReady()
    voiceAgentCapability.initializeWithLoadedModels(vadConfig)
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Status
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Check if Voice Agent is fully initialized and ready for use
 */
val RunAnywhere.isVoiceAgentReady: Boolean
    get() = voiceAgentCapability.isReady

/**
 * Get current Voice Agent pipeline state
 */
val RunAnywhere.voiceAgentPipelineState: VoiceAgentPipelineState
    get() = voiceAgentCapability.currentPipelineState

/**
 * Check if Voice Agent is currently processing audio
 */
val RunAnywhere.isVoiceAgentProcessing: Boolean
    get() = voiceAgentCapability.isProcessing

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
    return voiceAgentCapability.processVoiceTurn(audioData)
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
    return voiceAgentCapability.processStream(audioStream)
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
    return voiceAgentCapability.transcribe(audioData)
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
    return voiceAgentCapability.generateResponse(prompt)
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
    return voiceAgentCapability.synthesizeSpeech(text)
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Cleanup
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Cleanup Voice Agent and release all resources
 */
suspend fun RunAnywhere.cleanupVoiceAgent() {
    voiceAgentCapability.cleanup()
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Voice Session (High-level API matching iOS)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Start a voice session with real-time speech detection.
 * Matches iOS startVoiceSession() exactly.
 *
 * This is the simplest way to integrate voice assistant.
 * The session handles audio capture, VAD, and processing internally.
 *
 * Example:
 * ```kotlin
 * val session = RunAnywhere.startVoiceSession()
 *
 * // Consume events
 * session.events.collect { event ->
 *     when (event) {
 *         is VoiceSessionEvent.Listening -> audioMeter = event.audioLevel
 *         is VoiceSessionEvent.SpeechStarted -> showSpeechIndicator()
 *         is VoiceSessionEvent.Processing -> status = "Processing..."
 *         is VoiceSessionEvent.TurnCompleted -> {
 *             userText = event.transcript
 *             assistantText = event.response
 *         }
 *         is VoiceSessionEvent.Stopped -> break
 *         else -> {}
 *     }
 * }
 * ```
 *
 * @param config Session configuration (optional). Use VoiceSessionConfig.sensitive() for whisper detection.
 * @return Session handle with events flow
 */
suspend fun RunAnywhere.startVoiceSession(config: VoiceSessionConfig = VoiceSessionConfig.default): VoiceSessionHandle {
    requireInitialized()
    ensureServicesReady()
    val session = VoiceSessionHandle(config)
    session.start()
    return session
}
