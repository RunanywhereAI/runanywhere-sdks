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
// v3.1: VoiceAgentResult / VoiceSessionEvent imports removed — the
// expect declarations that used them (processVoice / startVoiceSession /
// streamVoiceSession) were deleted.

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
 * v3.1: Call before constructing a VoiceAgentStreamAdapter. In the
 * but can be called explicitly for more control.
 *
 * @throws SDKException if SDK is not initialized
 * @throws SDKException if any component models are not loaded
 * @throws SDKException if VoiceAgent initialization fails
 */
expect suspend fun RunAnywhere.initializeVoiceAgentWithLoadedModels()

// v3.1: processVoice / startVoiceSession / streamVoiceSession expect
// declarations DELETED. Replacements:
//   - Streaming: CppBridgeVoiceAgent.getHandle() + VoiceAgentStreamAdapter(handle)
//   - One-shot:  compose CppBridgeSTT.transcribe → CppBridgeLLM.generate → CppBridgeTTS.synthesize
// See the Android sample's processVoiceTurnDirect helper for the canonical
// one-shot composition pattern.

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

// ─────────────────────────────────────────────────────────────────────────────
// Phase 4a — VoiceAgent processing parity with Swift's
// RunAnywhere+VoiceAgent.swift (`processVoiceTurn`, `voiceAgentTranscribe`,
// `voiceAgentGenerateResponse`, `voiceAgentSynthesizeSpeech`,
// `cleanupVoiceAgent`).
//
// These are *one-shot* helpers that compose the individual
// STT/LLM/TTS bridges. They live here so cross-platform consumers can
// migrate from Swift's API one-to-one. New code should still prefer the
// streaming `VoiceAgentStreamAdapter` in
// `com.runanywhere.sdk.adapters.VoiceAgentStreamAdapter`.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Process a complete voice turn: audio -> transcription -> LLM response ->
 * synthesized speech.
 *
 * Mirrors Swift's `RunAnywhere.processVoiceTurn(_ audioData:)`.
 *
 * @param audioData PCM audio bytes (16 kHz / 16-bit mono recommended).
 * @return [VoiceAgentResult] with the transcript, response, and audio.
 */
expect suspend fun RunAnywhere.processVoiceTurn(
    audioData: ByteArray,
): com.runanywhere.sdk.public.extensions.VoiceAgent.VoiceAgentResult

/**
 * Transcribe audio using the voice-agent's STT component.
 *
 * Mirrors Swift's `RunAnywhere.voiceAgentTranscribe(_ audioData:)`.
 */
expect suspend fun RunAnywhere.voiceAgentTranscribe(audioData: ByteArray): String

/**
 * Generate an LLM response using the voice-agent's LLM component.
 *
 * Mirrors Swift's `RunAnywhere.voiceAgentGenerateResponse(_ prompt:)`.
 */
expect suspend fun RunAnywhere.voiceAgentGenerateResponse(prompt: String): String

/**
 * Synthesize speech using the voice-agent's TTS component.
 *
 * Mirrors Swift's `RunAnywhere.voiceAgentSynthesizeSpeech(_ text:)`.
 */
expect suspend fun RunAnywhere.voiceAgentSynthesizeSpeech(text: String): ByteArray

/**
 * Cleanup voice-agent resources.
 *
 * Mirrors Swift's `RunAnywhere.cleanupVoiceAgent()`.
 */
expect suspend fun RunAnywhere.cleanupVoiceAgent()
