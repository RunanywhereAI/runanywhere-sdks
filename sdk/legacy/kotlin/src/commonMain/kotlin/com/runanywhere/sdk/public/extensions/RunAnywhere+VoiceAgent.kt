/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for VoiceAgent operations.
 * Provides voice conversation capabilities combining STT, LLM, and TTS.
 *
 * Mirrors Swift RunAnywhere+VoiceAgent.swift pattern.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.VoiceAgent.VoiceAgentComponentStates
import com.runanywhere.sdk.public.extensions.VoiceAgent.VoiceAgentConfiguration
import com.runanywhere.sdk.public.extensions.VoiceAgent.VoiceAgentResult
import com.runanywhere.sdk.public.extensions.VoiceAgent.VoiceSessionConfig
import com.runanywhere.sdk.public.extensions.VoiceAgent.VoiceSessionEvent
import kotlinx.coroutines.flow.Flow

// MARK: - Voice Agent Configuration

/**
 * Configure the voice agent.
 *
 * @param configuration Voice agent configuration
 */
expect suspend fun RunAnywhere.configureVoiceAgent(configuration: VoiceAgentConfiguration)

/**
 * Get current voice agent component states.
 *
 * @return Current state of all voice agent components
 */
expect suspend fun RunAnywhere.voiceAgentComponentStates(): VoiceAgentComponentStates

/**
 * Check if the voice agent is fully ready (all components loaded).
 *
 * @return True if ready
 */
expect suspend fun RunAnywhere.isVoiceAgentReady(): Boolean

/**
 * Initialize the voice agent with currently loaded models.
 *
 * This function checks that STT, LLM, and TTS models are loaded,
 * then initializes the VoiceAgent orchestration component with those models.
 *
 * This is automatically called by startVoiceSession() if needed,
 * but can be called explicitly for more control.
 *
 * @throws SDKError if SDK is not initialized
 * @throws SDKError if any component models are not loaded
 * @throws SDKError if VoiceAgent initialization fails
 */
expect suspend fun RunAnywhere.initializeVoiceAgentWithLoadedModels()

// MARK: - Voice Processing

/**
 * Process audio through the voice pipeline (VAD -> STT -> LLM -> TTS).
 *
 * @param audioData Audio data to process
 * @return Voice agent result with transcription, response, and synthesized audio
 */
expect suspend fun RunAnywhere.processVoice(audioData: ByteArray): VoiceAgentResult

// MARK: - Voice Session

/**
 * Start a voice session.
 *
 * Returns a Flow of voice session events.
 *
 * Example:
 * ```kotlin
 * RunAnywhere.startVoiceSession()
 *     .collect { event ->
 *         when (event) {
 *             is VoiceSessionEvent.Listening -> // Show listening UI
 *             is VoiceSessionEvent.Transcribed -> println(event.text)
 *             is VoiceSessionEvent.Responded -> println(event.text)
 *             // ...
 *         }
 *     }
 * ```
 *
 * @param config Session configuration
 * @return Flow of voice session events
 */
expect fun RunAnywhere.startVoiceSession(
    config: VoiceSessionConfig = VoiceSessionConfig.DEFAULT,
): Flow<VoiceSessionEvent>

/**
 * Stream a voice session with automatic silence detection.
 *
 * This is the recommended API for voice pipelines. It handles:
 * - Audio level calculation for visualization
 * - Speech detection (when audio level > threshold)
 * - Automatic silence detection (triggers processing after silence duration)
 * - STT → LLM → TTS pipeline orchestration
 * - Continuous conversation mode (auto-resumes listening after TTS)
 *
 * The app only needs to:
 * 1. Capture audio and emit chunks to the input Flow
 * 2. Collect events to update UI
 * 3. Play audio when TurnCompleted event is received (if autoPlayTTS is false)
 *
 * Example:
 * ```kotlin
 * // Audio capture Flow from your audio service
 * val audioChunks: Flow<ByteArray> = audioCaptureService.startCapture()
 *
 * RunAnywhere.streamVoiceSession(audioChunks)
 *     .collect { event ->
 *         when (event) {
 *             is VoiceSessionEvent.Started -> showListeningUI()
 *             is VoiceSessionEvent.Listening -> updateAudioLevel(event.audioLevel)
 *             is VoiceSessionEvent.SpeechStarted -> showSpeechDetected()
 *             is VoiceSessionEvent.Processing -> showProcessingUI()
 *             is VoiceSessionEvent.Transcribed -> showTranscript(event.text)
 *             is VoiceSessionEvent.Responded -> showResponse(event.text)
 *             is VoiceSessionEvent.TurnCompleted -> {
 *                 // Play audio if autoPlayTTS is false
 *                 event.audio?.let { playAudio(it) }
 *             }
 *             is VoiceSessionEvent.Stopped -> showIdleUI()
 *             is VoiceSessionEvent.Error -> showError(event.message)
 *         }
 *     }
 * ```
 *
 * @param audioChunks Flow of audio chunks (16kHz, mono, 16-bit PCM)
 * @param config Session configuration (silence duration, speech threshold, etc.)
 * @return Flow of voice session events
 */
expect fun RunAnywhere.streamVoiceSession(
    audioChunks: Flow<ByteArray>,
    config: VoiceSessionConfig = VoiceSessionConfig.DEFAULT,
): Flow<VoiceSessionEvent>

/**
 * Stop the current voice session.
 */
expect suspend fun RunAnywhere.stopVoiceSession()

/**
 * Check if a voice session is active.
 *
 * @return True if a session is running
 */
expect suspend fun RunAnywhere.isVoiceSessionActive(): Boolean

// MARK: - Conversation History

/**
 * Clear the voice agent conversation history.
 */
expect suspend fun RunAnywhere.clearVoiceConversation()

/**
 * Set the system prompt for LLM responses.
 *
 * @param prompt System prompt text
 */
expect suspend fun RunAnywhere.setVoiceSystemPrompt(prompt: String)
