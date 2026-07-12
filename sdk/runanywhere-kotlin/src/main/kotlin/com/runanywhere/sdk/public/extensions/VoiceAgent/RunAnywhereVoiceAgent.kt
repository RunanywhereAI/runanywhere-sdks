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
import ai.runanywhere.proto.v1.ErrorCategory
import ai.runanywhere.proto.v1.ErrorCode
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelLoadRequest
import ai.runanywhere.proto.v1.SDKComponent
import ai.runanywhere.proto.v1.VoiceAgentResult
import ai.runanywhere.proto.v1.VoiceEvent
import com.runanywhere.sdk.adapters.VoiceAgentStreamAdapter
import com.runanywhere.sdk.features.VoiceAgent.Services.VoiceAgentMicDriver
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelLifecycle
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVoiceAgent
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAVoiceAgentComponentStates
import com.runanywhere.sdk.public.types.RAVoiceAgentComposeConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

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

/**
 * Swift-parity guard failure: mirrors Swift's plain
 * `SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)`,
 * which is constructed without logging.
 */
private fun notInitializedException(): SDKException =
    SDKException.make(
        code = ErrorCode.ERROR_CODE_NOT_INITIALIZED,
        message = "SDK not initialized",
        category = ErrorCategory.ERROR_CATEGORY_INTERNAL,
        shouldLog = false,
    )

private fun isComponentReady(component: SDKComponent): Boolean =
    CppBridgeModelLifecycle.snapshot(component)?.let {
        it.state == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY &&
            it.model_id.isNotEmpty()
    } ?: false

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
suspend fun RunAnywhere.ensureDefaultVAD(modelID: String? = null): Boolean {
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
    if (!isInitialized) throw notInitializedException()
    ensureServicesReady()
    val states =
        CppBridgeVoiceAgent.initialize(
            CppBridgeVoiceAgent.getHandle(),
            config,
        )
    voiceAgentLogger.info("Voice agent initialized from RAVoiceAgentComposeConfig: ready=${states.ready}")
}

suspend fun RunAnywhere.getVoiceAgentComponentStates(): RAVoiceAgentComponentStates {
    if (!isInitialized) throw notInitializedException()
    ensureServicesReady()
    return CppBridgeVoiceAgent.states(CppBridgeVoiceAgent.getHandle())
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
 * Swift comment at `RunAnywhere+VoiceAgent.swift:152-161`).
 */
suspend fun RunAnywhere.initializeVoiceAgentWithLoadedModels(
    ttsVoiceId: String? = null,
    ensureVAD: Boolean = true,
) {
    if (!isInitialized) throw notInitializedException()
    ensureServicesReady()

    if (ensureVAD) {
        ensureDefaultVAD()
    }

    val missing = getMissingComponents()
    if (missing.isNotEmpty()) {
        throw SDKException.make(
            code = ErrorCode.ERROR_CODE_MODEL_NOT_LOADED,
            message = "Cannot initialize voice agent: Models not loaded: ${missing.joinToString(", ")}",
            category = ErrorCategory.ERROR_CATEGORY_COMPONENT,
            shouldLog = false,
        )
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
    voiceAgentLogger.info(
        "VoiceAgent initialized from loaded models (ttsVoiceId=${ttsVoiceId ?: "<default>"}, ready=${states.ready})",
    )
}

/**
 * Cleanup voice agent resources. Never throws and is safe to call at any
 * time, whether or not the SDK or the voice agent is initialized.
 * Mirrors Swift `cleanupVoiceAgent()` → `CppBridge.VoiceAgent.cleanup()`,
 * which releases owned child components while keeping the handle alive.
 */
suspend fun RunAnywhere.cleanupVoiceAgent() {
    CppBridgeVoiceAgent.cleanup()
}

suspend fun RunAnywhere.processVoiceTurn(audioData: ByteArray): VoiceAgentResult {
    if (!isInitialized) throw notInitializedException()
    ensureServicesReady()
    if (!CppBridgeVoiceAgent.isReady()) {
        throw SDKException.make(
            code = ErrorCode.ERROR_CODE_NOT_INITIALIZED,
            message = "Voice agent not ready",
            category = ErrorCategory.ERROR_CATEGORY_COMPONENT,
            shouldLog = false,
        )
    }
    return CppBridgeVoiceAgent.processVoiceTurnProto(audioData)
}

/**
 * Open a stream of canonical [VoiceEvent] proto events for the active
 * voice agent.
 *
 * The C ABI owns no microphone (rac_voice_agent.h audio-ingress contract):
 * subscribing to the handle callback alone is dead air. While the returned
 * flow is collected, a [VoiceAgentMicDriver] captures mic audio, segments
 * utterances, and drives per-utterance turns whose VoiceEvents fan out to
 * this same handle callback. Cancelling the collector stops capture and
 * tears down the underlying C callback via [VoiceAgentStreamAdapter].
 *
 * Setup failures (SDK not initialized, services not ready, handle or mic
 * acquisition) propagate to the collector so callers can surface them —
 * they are not swallowed silently.
 *
 * Behavior change: earlier builds returned a silent/empty flow when a setup
 * step failed; collectors now observe the exception instead. Wrap collection
 * in try/catch (or `Flow.catch`) to handle it.
 *
 * @throws SDKException when the SDK is not initialized, or voice-agent
 *   services/handle cannot be acquired (delivered to the flow collector).
 */
fun RunAnywhere.streamVoiceAgent(): Flow<VoiceEvent> =
    flow {
        if (!isInitialized) throw notInitializedException()
        ensureServicesReady()
        val handle = CppBridgeVoiceAgent.getHandle()
        coroutineScope {
            val driver = launch(Dispatchers.IO) { VoiceAgentMicDriver(handle).run() }
            try {
                emitAll(VoiceAgentStreamAdapter(handle).stream())
            } finally {
                // Cancellation of a coroutine blocked in JNI is cooperative:
                // wait for the active feed/turn to return and for the driver's
                // finally block to stop AudioRecord before this stream is
                // considered closed. This prevents a retained Talk screen from
                // continuing to feed the shared STT model after navigation.
                withContext(NonCancellable) { driver.cancelAndJoin() }
            }
        }
    }
