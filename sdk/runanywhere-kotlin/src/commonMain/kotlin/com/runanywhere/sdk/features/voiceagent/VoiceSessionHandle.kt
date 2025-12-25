package com.runanywhere.sdk.features.voiceagent

import kotlinx.coroutines.flow.Flow

/**
 * Handle to control an active voice session.
 * Matches iOS VoiceSessionHandle exactly.
 *
 * This class manages the complete voice conversation loop:
 * 1. Audio capture
 * 2. Real-time speech detection (energy-based VAD)
 * 3. Audio buffering during speech
 * 4. Processing when speech ends (STT → LLM → TTS)
 * 5. Audio playback of response
 *
 * Usage:
 * ```kotlin
 * val session = RunAnywhere.startVoiceSession()
 * session.events.collect { event ->
 *     when (event) {
 *         is VoiceSessionEvent.Listening -> updateAudioMeter(event.audioLevel)
 *         is VoiceSessionEvent.SpeechStarted -> showSpeechIndicator()
 *         is VoiceSessionEvent.Processing -> showProcessingIndicator()
 *         is VoiceSessionEvent.TurnCompleted -> updateUI(event.transcript, event.response)
 *         else -> {}
 *     }
 * }
 * ```
 */
expect class VoiceSessionHandle(
    config: VoiceSessionConfig,
) {
    /** Stream of session events */
    val events: Flow<VoiceSessionEvent>

    /** Start the voice session */
    suspend fun start()

    /** Stop the voice session */
    fun stop()

    /** Force process current audio (push-to-talk) */
    suspend fun sendNow()
}
