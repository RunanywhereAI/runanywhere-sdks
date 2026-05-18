/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for VoiceAgent operations.
 *
 * v2 close-out Phase 6 (P2-1): all orchestration bodies that re-implemented
 * the STT → LLM → TTS pipeline in Kotlin have been deleted. The streaming
 * surface (`streamVoiceAgent`) is the canonical voice-agent entry point.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.ComponentLifecycleState
import ai.runanywhere.proto.v1.SDKComponent
import ai.runanywhere.proto.v1.VoiceAgentConfig
import ai.runanywhere.proto.v1.VoiceAgentResult
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelLifecycle
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVoiceAgent
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAVoiceAgentComponentStates
import com.runanywhere.sdk.public.types.RAVoiceAgentComposeConfig

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

actual suspend fun RunAnywhere.initializeVoiceAgent(config: VoiceAgentConfig) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    voiceAgentInitialized = false
    // pass3-syn-030 / pass3-syn-025: prefer the caller-supplied tts_voice_id
    // (added to VoiceAgentConfig in idl/solutions.proto) over the legacy
    // tts_model_id fallback. Multi-voice TTS engines (Piper, eSpeak-NG,
    // Sherpa-ONNX-TTS multi-voice) need a distinct voice id; single-voice
    // engines pass empty tts_voice_id and the fallback uses tts_model_id.
    //
    // Until the generated VoiceAgentConfig is regenerated with the new
    // tts_voice_id field, the access goes through a reflective lookup so
    // this code compiles against both the pre- and post-codegen shapes.
    val resolvedTtsVoiceId = resolveTtsVoiceId(config)
    val composeConfig =
        RAVoiceAgentComposeConfig(
            stt_model_id = config.stt_model_id.takeIf { it.isNotBlank() },
            llm_model_id = config.llm_model_id.takeIf { it.isNotBlank() },
            tts_voice_id = resolvedTtsVoiceId,
            vad_sample_rate = config.sample_rate_hz,
        )
    val states =
        CppBridgeVoiceAgent.initialize(
            CppBridgeVoiceAgent.getRawHandle(),
            composeConfig,
        )
    voiceAgentInitialized = states.ready
    voiceAgentLogger.info("Voice agent initialized from VoiceAgentConfig: ready=${states.ready}")
}

/**
 * pass3-syn-030: resolves the TTS voice id for a [VoiceAgentConfig], preferring
 * the new `tts_voice_id` field added in pass3-syn-025 over the legacy
 * `tts_model_id` fallback.
 *
 * Uses reflection so this compiles regardless of whether the Wire-generated
 * proto has been regenerated to include `tts_voice_id`. Once the codegen
 * lands the field, this helper can be inlined to a direct accessor:
 *
 *     val resolved = config.tts_voice_id.takeIf { it.isNotBlank() }
 *         ?: config.tts_model_id.takeIf { it.isNotBlank() }
 */
private fun resolveTtsVoiceId(config: VoiceAgentConfig): String? {
    val newField =
        try {
            val getter =
                config::class.java.methods
                    .firstOrNull { it.name == "getTts_voice_id" || it.name == "getTtsVoiceId" }
            (getter?.invoke(config) as? String)?.takeIf { it.isNotBlank() }
        } catch (_: Throwable) {
            null
        }
    return newField ?: config.tts_model_id.takeIf { it.isNotBlank() }
}

actual suspend fun RunAnywhere.getVoiceAgentComponentStates(): RAVoiceAgentComponentStates {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    return CppBridgeVoiceAgent.states(CppBridgeVoiceAgent.getRawHandle())
}

actual suspend fun RunAnywhere.initializeVoiceAgentWithLoadedModels() {
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

actual suspend fun RunAnywhere.cleanupVoiceAgent() {
    // Match Swift: cleanup voice-agent handle + reset flag.
    voiceAgentInitialized = false
    CppBridgeVoiceAgent.destroy()
}

actual suspend fun RunAnywhere.processVoiceTurn(audioData: ByteArray): VoiceAgentResult {
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

actual fun RunAnywhere.streamVoiceAgent(): kotlinx.coroutines.flow.Flow<ai.runanywhere.proto.v1.VoiceEvent> {
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
