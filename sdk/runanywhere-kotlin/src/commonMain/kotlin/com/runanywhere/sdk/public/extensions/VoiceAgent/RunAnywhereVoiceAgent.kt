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

import ai.runanywhere.proto.v1.VoiceAgentConfig
import ai.runanywhere.proto.v1.VoiceAgentResult
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAVoiceAgentComponentStates

/**
 * Canonical alias: the proto `VoiceAgentComponentStates` is the `ComponentStates`
 * type referenced in §10 of CANONICAL_API.md. SDK consumers can use either name.
 */
typealias ComponentStates = RAVoiceAgentComponentStates

// MARK: - Voice Agent Configuration

/**
 * Initialize the voice agent with a configuration.
 *
 * Canonical cross-SDK name. Replaces the deleted `configureVoiceAgent`.
 *
 * @param config Proto [VoiceAgentConfig] specifying model IDs for each component
 */
expect suspend fun RunAnywhere.initializeVoiceAgent(config: VoiceAgentConfig)

/**
 * Get current voice agent component states.
 *
 * @return [ComponentStates] (alias for [VoiceAgentComponentStates]) proto message
 *         with per-component load state and computed readiness flags.
 */
expect suspend fun RunAnywhere.getVoiceAgentComponentStates(): ComponentStates

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

/**
 * Cleanup voice-agent resources.
 *
 * Mirrors Swift's `RunAnywhere.cleanupVoiceAgent()`.
 */
expect suspend fun RunAnywhere.cleanupVoiceAgent()

/**
 * Process a complete voice turn end-to-end (VAD → STT → LLM → TTS) over the
 * composite voice-agent handle.
 *
 * Mirrors Swift's `RunAnywhere.processVoiceTurn(_:)`:
 *  - Lazily completes Phase 2 (`ensureServicesReady`).
 *  - Verifies the SDK is initialized and the voice-agent handle is ready.
 *  - Forwards to `CppBridgeVoiceAgent.processVoiceTurnProto(audioData)` which
 *    wraps `rac_voice_agent_process_voice_turn_proto`.
 *
 * @param audioData raw audio bytes for the turn (PCM16 mono unless the
 *   component was configured otherwise via [initializeVoiceAgent]).
 * @return the canonical [VoiceAgentResult] proto carrying transcript,
 *   response text, synthesized audio, and per-stage timings.
 * @throws SDKException if the SDK is not initialized, the voice agent is
 *   not ready, or the C ABI returns null / decoding fails.
 */
expect suspend fun RunAnywhere.processVoiceTurn(audioData: ByteArray): VoiceAgentResult

// ─────────────────────────────────────────────────────────────────────────────
// Round 1 KOTLIN (Task 7 / G-E4): canonical streaming voice-agent entry-point.
//
// Iron Rule 5: example apps MUST NOT call CppBridgeVoiceAgent directly.
// `streamVoiceAgent()` is the public surface that replaces the pattern:
//     val handle = CppBridgeVoiceAgent.getHandle()
//     VoiceAgentStreamAdapter(handle).stream()
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Create or reuse the voice-agent handle and return a proto event stream.
 *
 * Internally allocates a [VoiceAgentStreamAdapter] backed by the singleton
 * voice-agent handle. The stream closes when the collecting coroutine is
 * cancelled; call [cleanupVoiceAgent] afterwards to release the native handle.
 *
 * Requires STT/LLM/TTS models to be loaded before calling.
 *
 * @throws SDKException if models are not loaded or the native handle
 *         allocation fails.
 */
expect fun RunAnywhere.streamVoiceAgent(): kotlinx.coroutines.flow.Flow<ai.runanywhere.proto.v1.VoiceEvent>
