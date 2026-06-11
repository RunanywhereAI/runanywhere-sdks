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
import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelLoadRequest
import ai.runanywhere.proto.v1.SDKComponent
import ai.runanywhere.proto.v1.VoiceAgentResult
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelLifecycle
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVoiceAgent
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAVoiceAgentComponentStates
import com.runanywhere.sdk.public.types.RAVoiceAgentComposeConfig
import kotlinx.coroutines.launch

/**
 * Canonical alias: the proto `VoiceAgentComponentStates` is the `ComponentStates`
 * type referenced in §10 of CANONICAL_API.md. SDK consumers can use either name.
 */
typealias ComponentStates = RAVoiceAgentComponentStates

// MARK: - Voice Agent Configuration

// Round 1 KOTLIN (Task 7 / G-E4): canonical streaming voice-agent entry-point.
//
// Iron Rule 5: example apps MUST NOT call CppBridgeVoiceAgent directly.
// `streamVoiceAgent()` is the public surface that replaces the pattern:
//     val handle = CppBridgeVoiceAgent.getHandle()
//     VoiceAgentStreamAdapter(handle).stream()

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

/**
 * Default Silero VAD model id seeded by every example app's catalog.
 * Exposed so callers do not hard-code the string when invoking
 * [ensureDefaultVAD]. Mirrors Swift `RunAnywhere.defaultVADModelID`.
 */
val RunAnywhere.defaultVADModelID: String
    get() = "silero-vad"

/**
 * Ensure a VAD model is loaded in the canonical lifecycle before a voice
 * agent session starts. When no VAD model is currently registered for
 * [ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION], attempts to
 * load the catalogued default ([defaultVADModelID], Silero) so the voice
 * agent's speech-start / speech-end events fire. The energy-based
 * fallback does not produce the lifecycle events the voice-agent
 * orchestrator listens for, so without a VAD lifecycle load the session
 * stays silent after init.
 *
 * Idempotent: returns `true` immediately when a VAD model is already
 * loaded. Logs (but does not throw) when the optional auto-load fails;
 * callers may inspect the return value to decide whether to surface a
 * warning. Mirrors Swift `ensureDefaultVAD(modelID:)`.
 *
 * @param modelID VAD model id to auto-load when none is current. When
 *   `null`, falls back to [defaultVADModelID].
 * @return `true` when a VAD model is loaded after the call; `false`
 *   when no VAD model is loaded (auto-load failed or skipped).
 */
suspend fun RunAnywhere.ensureDefaultVAD(
    modelID: String? = null,
): Boolean = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
    ensureDefaultVADBlocking(modelID)
}

// Blocking JNI body of [ensureDefaultVAD] — may download + load the Silero
// model. Kept separate so callers already on a worker dispatcher skip the
// extra hop.
private fun RunAnywhere.ensureDefaultVADBlocking(modelID: String? = null): Boolean {
    if (!isInitialized) return false

    val currentRequest =
        CurrentModelRequest(
            category = ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
        )
    val snapshot = CppBridgeModelLifecycle.currentModel(currentRequest)
    if (snapshot != null && snapshot.found && snapshot.model_id.isNotEmpty()) {
        return true
    }

    val targetID = modelID ?: defaultVADModelID
    if (targetID.isEmpty()) return false

    voiceAgentLogger.info("Auto-loading default VAD '$targetID' for voice-agent session")

    val loadRequest =
        ModelLoadRequest(
            model_id = targetID,
            category = ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
            // Auto-download when the catalogued entry has no local artifact:
            // lifecycle load rejects not-downloaded models, and the energy
            // fallback emits none of the lifecycle events the voice agent
            // needs — a missing Silero model means a silent session.
            validate_availability = true,
        )
    val result = CppBridgeModelLifecycle.load(loadRequest)
    if (result == null || !result.success) {
        val errorMessage = result?.error_message.orEmpty()
        voiceAgentLogger.warning(
            "Default VAD '$targetID' auto-load failed: $errorMessage — voice agent will use energy fallback",
        )
        return false
    }
    return true
}

suspend fun RunAnywhere.initializeVoiceAgent(config: RAVoiceAgentComposeConfig) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    ensureServicesReady()
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
    ensureServicesReady()
    return CppBridgeVoiceAgent.states(CppBridgeVoiceAgent.getRawHandle())
}

/**
 * Initialize the voice agent from currently-loaded STT / LLM / TTS models.
 *
 * Mirrors Swift `initializeVoiceAgentWithLoadedModels(ttsVoiceID:ensureVAD:)`.
 *
 * When [ensureVAD] is `true` (default), the SDK guarantees that a VAD
 * model is loaded into the canonical lifecycle before initialization
 * runs via [ensureDefaultVAD]. Without this the session would silently
 * fall back to the energy-based detector and the C++ voice agent's
 * speech-start / speech-end lifecycle events would not fire. Set to
 * `false` only if the caller has already loaded an explicit VAD model
 * (or knows the energy fallback is acceptable for the deployment).
 *
 * The [ttsVoiceId] parameter is the voice id **within** the loaded TTS
 * model, NOT the model id. For single-voice engines, leaving it `null`
 * (the default) lets the engine pick its default voice. For multi-voice
 * engines (Piper, eSpeak-NG, Sherpa-ONNX-TTS multi-voice), the caller
 * must supply the desired voice id explicitly; reusing the TTS model id
 * here produces invalid voice selection for multi-voice models (see
 * Swift comment at `RunAnywhere+VoiceAgent.swift:162-171`).
 */
suspend fun RunAnywhere.initializeVoiceAgentWithLoadedModels(
    ttsVoiceId: String? = null,
    ensureVAD: Boolean = true,
) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    ensureServicesReady()

    // Off-main: ensureDefaultVAD may download + load the Silero model
    // (validate_availability) and the snapshot/initialize calls are blocking
    // JNI. View-models call this from the main thread; running it there
    // froze the UI for the duration of the VAD bootstrap.
    kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
        if (ensureVAD) {
            ensureDefaultVADBlocking()
        }

        if (voiceAgentInitialized && areAllComponentsLoaded()) return@withContext
        if (!areAllComponentsLoaded()) {
            val missing = getMissingComponents()
            throw SDKException.voiceAgent("Cannot initialize: Models not loaded: ${missing.joinToString(", ")}")
        }

        val sttSnap = CppBridgeModelLifecycle.snapshot(SDKComponent.SDK_COMPONENT_STT)
        val llmSnap = CppBridgeModelLifecycle.snapshot(SDKComponent.SDK_COMPONENT_LLM)

        val composeConfig =
            RAVoiceAgentComposeConfig(
                stt_model_id = sttSnap?.model_id?.takeIf { it.isNotBlank() },
                llm_model_id = llmSnap?.model_id?.takeIf { it.isNotBlank() },
                tts_voice_id = ttsVoiceId?.takeIf { it.isNotBlank() },
            )

        val handle = CppBridgeVoiceAgent.getHandle()
        val states = CppBridgeVoiceAgent.initialize(handle, composeConfig)
        voiceAgentInitialized = states.ready
        voiceAgentLogger.info(
            "VoiceAgent initialized from loaded models (ttsVoiceId=${ttsVoiceId ?: "<default>"}, ready=${states.ready})",
        )
    }
}

suspend fun RunAnywhere.cleanupVoiceAgent() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    ensureServicesReady()
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

// Round 1 KOTLIN (Task 7 / G-E4): public streamVoiceAgent() entry-point.
// Replaces the pattern: CppBridgeVoiceAgent.getHandle() + VoiceAgentStreamAdapter(handle)
// that leaked CppBridge internals into example apps.

fun RunAnywhere.streamVoiceAgent(): kotlinx.coroutines.flow.Flow<ai.runanywhere.proto.v1.VoiceEvent> {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    // W3-6: composite getHandle() is now suspend (gathers from 4 sub-component
    // actors before composing). Defer the call into the Flow's coroutine
    // context via `flow { ... }` so the public API stays a non-suspend `fun`
    // returning Flow.
    //
    // The C ABI owns no microphone (rac_voice_agent.h audio-ingress
    // contract): subscribing to the handle callback alone is dead-air. While
    // the returned flow is collected, a VoiceAgentMicDriver captures mic
    // audio, segments utterances, and drives per-utterance turns whose
    // VoiceEvents fan out to this same handle callback. Cancelling the
    // collector tears down capture.
    return kotlinx.coroutines.flow.flow {
        ensureServicesReady()
        val handle = CppBridgeVoiceAgent.getHandle()
        kotlinx.coroutines.coroutineScope {
            val driver =
                launch(kotlinx.coroutines.Dispatchers.IO) {
                    com.runanywhere.sdk.features.VoiceAgent.Services
                        .VoiceAgentMicDriver(handle)
                        .run()
                }
            try {
                com.runanywhere.sdk.adapters
                    .VoiceAgentStreamAdapter(handle)
                    .stream()
                    .collect { event -> emit(event) }
            } finally {
                driver.cancel()
            }
        }
    }
}
