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
 * This is automatically called by startVoiceSession() if needed,
 * but can be called explicitly for more control.
 *
 * @throws SDKError if SDK is not initialized
 * @throws SDKError if any component models are not loaded
 * @throws SDKError if VoiceAgent initialization fails
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
