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

import ai.runanywhere.proto.v1.ComponentLifecycleState
import ai.runanywhere.proto.v1.SDKComponent
import ai.runanywhere.proto.v1.VoiceAgentResult
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelLifecycle
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVoiceAgent
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAVoiceAgentComponentStates
import com.runanywhere.sdk.public.types.RAVoiceAgentComposeConfig

/**
 * Canonical alias: the proto `VoiceAgentComponentStates` is the `ComponentStates`
 * type referenced in §10 of CANONICAL_API.md. SDK consumers can use either name.
 */
typealias ComponentStates = RAVoiceAgentComponentStates

// MARK: - Voice Agent Configuration

// ─────────────────────────────────────────────────────────────────────────────
// Round 1 KOTLIN (Task 7 / G-E4): canonical streaming voice-agent entry-point.
//
// Iron Rule 5: example apps MUST NOT call CppBridgeVoiceAgent directly.
// `streamVoiceAgent()` is the public surface that replaces the pattern:
//     val handle = CppBridgeVoiceAgent.getHandle()
//     VoiceAgentStreamAdapter(handle).stream()
// ─────────────────────────────────────────────────────────────────────────────

private val voiceAgentLogger = SDKLogger.voiceAgent

@Volatile private var voiceAgentInitialized: Boolean = false

private fun isComponentReady(component: SDKComponent): Boolean =
    CppBridgeModelLifecycle.snapshot(component)?.let {
        it.state == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY &&
            it.model_id.isNotEmpty()
    } ?: false

private fun areAllComponentsLoaded(): Boolean =
    isComponentReady(SDKComponent.SDK_COMPONENT_STT) &&
        isComponentReady(SDKComponent.SDK_COMPONENT_LLM) &&
        isComponentReady(SDKComponent.SDK_COMPONENT_TTS)

private fun getMissingComponents(): List<String> {
    val missing = mutableListOf<String>()
    if (!isComponentReady(SDKComponent.SDK_COMPONENT_STT)) missing.add("STT")
    if (!isComponentReady(SDKComponent.SDK_COMPONENT_LLM)) missing.add("LLM")
    if (!isComponentReady(SDKComponent.SDK_COMPONENT_TTS)) missing.add("TTS")
    return missing
}

suspend fun RunAnywhere.initializeVoiceAgent(config: RAVoiceAgentComposeConfig) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    voiceAgentInitialized = false
    val states =
        CppBridgeVoiceAgent.initialize(
            CppBridgeVoiceAgent.getRawHandle(),
            config,
        )
    voiceAgentInitialized = states.ready
    voiceAgentLogger.info("Voice agent initialized from RAVoiceAgentComposeConfig: ready=${states.ready}")
}

suspend fun RunAnywhere.getVoiceAgentComponentStates(): RAVoiceAgentComponentStates {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    return CppBridgeVoiceAgent.states(CppBridgeVoiceAgent.getRawHandle())
}

suspend fun RunAnywhere.initializeVoiceAgentWithLoadedModels() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    if (voiceAgentInitialized && areAllComponentsLoaded()) return
    if (!areAllComponentsLoaded()) {
        val missing = getMissingComponents()
        throw SDKException.voiceAgent("Cannot initialize: Models not loaded: ${missing.joinToString(", ")}")
    }
    CppBridgeVoiceAgent.getHandle()
    voiceAgentInitialized = true
    voiceAgentLogger.info("VoiceAgent initialized successfully")
}

suspend fun RunAnywhere.cleanupVoiceAgent() {
    // Match Swift: cleanup voice-agent handle + reset flag.
    voiceAgentInitialized = false
    CppBridgeVoiceAgent.destroy()
}

suspend fun RunAnywhere.processVoiceTurn(audioData: ByteArray): VoiceAgentResult {
    // Mirror Swift RunAnywhere+VoiceAgent.processVoiceTurn(_:) one-for-one:
    //   try await ensureServicesReady()
    //   guard isInitialized else { throw .notInitialized("voiceagent") }
    //   guard await CppBridge.VoiceAgent.shared.isReady else { throw .invalidState(...) }
    //   return try await CppBridge.VoiceAgent.shared.processVoiceTurnProto(audioData)
    ensureServicesReady()
    if (!isInitialized) throw SDKException.notInitialized("voiceagent")
    if (!CppBridgeVoiceAgent.isReady()) {
        throw SDKException.invalidState("VoiceAgent not initialized")
    }
    return CppBridgeVoiceAgent.processVoiceTurnProto(audioData)
}

// ─────────────────────────────────────────────────────────────────────────────
// Round 1 KOTLIN (Task 7 / G-E4): public streamVoiceAgent() entry-point.
// Replaces the pattern: CppBridgeVoiceAgent.getHandle() + VoiceAgentStreamAdapter(handle)
// that leaked CppBridge internals into example apps.
// ─────────────────────────────────────────────────────────────────────────────

fun RunAnywhere.streamVoiceAgent(): kotlinx.coroutines.flow.Flow<ai.runanywhere.proto.v1.VoiceEvent> {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    // W3-6: composite getHandle() is now suspend (gathers from 4 sub-component
    // actors before composing). Defer the call into the Flow's coroutine
    // context via `flow { ... }` + `emitAll` so the public API stays a
    // non-suspend `fun` returning Flow.
    return kotlinx.coroutines.flow.flow {
        val handle = CppBridgeVoiceAgent.getHandle()
        com.runanywhere.sdk.adapters
            .VoiceAgentStreamAdapter(handle)
            .stream()
            .collect { event -> emit(event) }
    }
}
