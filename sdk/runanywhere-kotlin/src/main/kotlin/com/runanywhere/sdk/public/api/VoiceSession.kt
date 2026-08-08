/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v3 surface: `RunAnywhere.voice` and the live session it creates.
 */

package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.PipelineState
import ai.runanywhere.proto.v1.TurnLifecycleEventKind
import ai.runanywhere.proto.v1.VADStreamEventKind
import ai.runanywhere.proto.v1.VoiceAgentComposeConfig
import com.runanywhere.sdk.adapters.VoiceAgentStreamAdapter
import com.runanywhere.sdk.features.VoiceAgent.Services.VoiceAgentMicDriver
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVoiceAgent
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.generated.RADefaults
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.launch
import ai.runanywhere.proto.v1.TokenKind as ProtoTokenKind
import ai.runanywhere.proto.v1.VoiceEvent as ProtoVoiceEvent

private val voiceLogger = SDKLogger.voiceAgent

/**
 * A live voice conversation that owns its models, VAD, and microphone.
 *
 * Create it with [VoiceNamespace.createSession]. Subscribing to [events] does
 * not open the microphone; [start] is the only thing that does.
 */
public class VoiceSession internal constructor(
    private val handle: Long,
    private val ttsVoice: String?,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var micJob: Job? = null

    /**
     * The live capture/playout driver, retained so [interrupt] can reach the playback it
     * owns. Without the reference, barge-in had nothing to stop — see [interrupt].
     */
    @Volatile
    private var micDriver: VoiceAgentMicDriver? = null

    /**
     * Playout phase reported by the mic driver. Kept off the core's stream on
     * purpose: the core emits `PLAYING_TTS` before synthesis and hands the audio
     * back for the platform to play, so it cannot say when sound starts or stops.
     */
    private val playbackPhase =
        MutableSharedFlow<VoiceEvent>(replay = 0, extraBufferCapacity = 8)

    /**
     * Turn-by-turn progress of the conversation.
     *
     * Merges the core's own voice events with the driver's real playout phase, so
     * a subscriber is told "speaking" exactly while the reply is audible — and is
     * told when it stops. Mirrors Swift `VoiceSession.events`.
     */
    public val events: Flow<VoiceEvent> =
        merge(
            VoiceAgentStreamAdapter(handle).stream().mapNotNull { it.toVoiceEvent() },
            playbackPhase,
        )

    /**
     * Open the microphone and begin taking turns.
     *
     * @throws SDKException when audio capture cannot start.
     */
    public fun start() {
        if (micJob?.isActive == true) return
        val driver =
            VoiceAgentMicDriver(handle) { phase ->
                playbackPhase.tryEmit(VoiceEvent.AgentStateChanged(phase))
            }
        micDriver = driver
        micJob = scope.launch(Dispatchers.IO) { driver.run() }
    }

    /**
     * Speak [text] now, outside the turn loop, returning immediately with a
     * handle to the in-flight utterance.
     */
    public fun say(text: String): SpeechHandle {
        val handle = SpeechHandle(interruptHandler = { legacyStopSpeaking() })
        scope.launch(Dispatchers.IO) {
            try {
                legacySpeak(text, TtsOptions(voice = ttsVoice).toProto())
                handle.complete()
            } catch (error: SDKException) {
                handle.complete(error)
            }
        }
        return handle
    }

    /**
     * Stop the agent mid-utterance. Awaitable: suspends until the interrupted
     * response, its tools, and its playout have all settled.
     *
     * A turn's reply is played out by the mic driver's own playback manager, not by the
     * TTS namespace's singleton, so stopping only the latter left the agent talking to the
     * end of its buffer while the UI claimed the turn had been handed back. The driver is
     * silenced first — that is the part the user hears — and `legacyStopSpeaking` still
     * runs afterwards to cancel any synthesis the TTS path itself has in flight.
     */
    public suspend fun interrupt() {
        micDriver?.stopPlayback()
        legacyStopSpeaking()
    }

    /** Stop capture, release the pipeline's components, and end the session. */
    public suspend fun close() {
        micDriver?.stopPlayback()
        micDriver = null
        micJob?.cancelAndJoin()
        micJob = null
        scope.cancel()
        CppBridgeVoiceAgent.cleanup()
        voiceLogger.info("Voice session closed")
    }
}

/**
 * Live voice conversations combining STT, an LLM, and TTS.
 *
 * ```kotlin
 * val session = RunAnywhere.voice.createSession(ModelRef("whisper-tiny"), ModelRef("qwen3-0.6b"), ModelRef("piper-en"))
 * session.start()
 * ```
 */
public class VoiceNamespace internal constructor() {
    /**
     * Build a session over the given models, downloading and loading each one
     * and ensuring a VAD is resident.
     *
     * @throws SDKException when a model cannot be loaded or the pipeline cannot
     *   be composed.
     */
    @Suppress("LongParameterList")
    public suspend fun createSession(
        stt: ModelRef,
        llm: ModelRef,
        tts: ModelRef,
        vad: VadOptions? = null,
        turnHandling: TurnHandlingOptions? = null,
        generation: LlmOptions? = null,
        downloadIfNeeded: Boolean = true,
    ): VoiceSession {
        RunAnywhere.ensureServicesReady()

        ensureModelLoaded(
            stt.id,
            ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
            downloadIfNeeded = downloadIfNeeded,
        )
        ensureModelLoaded(
            llm.id,
            ModelCategory.MODEL_CATEGORY_LANGUAGE,
            downloadIfNeeded = downloadIfNeeded,
        )
        ensureModelLoaded(
            tts.id,
            ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
            downloadIfNeeded = downloadIfNeeded,
        )
        ensureVadResident(downloadIfNeeded)

        val handle = CppBridgeVoiceAgent.getHandle()
        val states =
            CppBridgeVoiceAgent.initialize(
                handle,
                VoiceAgentComposeConfig(
                    stt_model_id = stt.id,
                    llm_model_id = llm.id,
                    tts_voice_id = tts.voice?.takeIf { it.isNotBlank() },
                ),
            )
        if (!states.ready) {
            throw SDKException.invalidState(
                states.error?.message?.takeIf { it.isNotBlank() }
                    ?: "Voice pipeline did not come up ready",
            )
        }
        if (vad != null || turnHandling != null || generation != null) {
            voiceLogger.debug(
                "VAD, turn-handling, and generation overrides are not carried by the commons " +
                    "voice-agent compose ABI yet",
            )
        }
        return VoiceSession(handle, tts.voice)
    }

    private suspend fun ensureVadResident(downloadIfNeeded: Boolean) {
        val defaultVad = RADefaults.VoiceAgent.DEFAULT_VAD_MODEL_ID
        if (defaultVad.isEmpty()) return
        val current =
            legacyCurrentModel(
                CurrentModelRequest(
                    category = ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
                ),
            )
        if (current.found && current.model_id.isNotEmpty()) return
        runCatching {
            ensureModelLoaded(
                defaultVad,
                ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
                downloadIfNeeded = downloadIfNeeded,
            )
        }.onFailure { error ->
            voiceLogger.warning("Default VAD '$defaultVad' unavailable: ${error.message}")
        }
    }
}

/**
 * `SpeechTurnDetectionEventKind` and `VoiceEvent.speech_turn_detection` are
 * deleted outright (idl/voice_events.proto): agent-response start/complete
 * and user-speech start/end are now `TurnLifecycleEventKind` values on
 * `turn_lifecycle`, not a separate oneof arm. `VoiceEvent.error` (a bare
 * `SDKError`) never existed on the wire either -- `session_error`
 * (`VoiceSessionError`, field `recoverable`, no `is_` prefix) is the one
 * error payload in this domain.
 */
private fun ProtoVoiceEvent.toVoiceEvent(): VoiceEvent? {
    user_said?.let { return VoiceEvent.UserTranscribed(it.text, it.is_final) }
    assistant_token?.let { token ->
        if (token.is_final && token.text.isNotEmpty()) return VoiceEvent.AgentResponse(token.text)
        if (token.kind == ProtoTokenKind.TOKEN_KIND_ANSWER && token.text.isNotEmpty()) {
            return VoiceEvent.AgentResponse(token.text)
        }
    }
    turn_lifecycle?.let { turn ->
        when (turn.kind) {
            TurnLifecycleEventKind.TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_STARTED ->
                return VoiceEvent.SpeechStarted()
            TurnLifecycleEventKind.TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_ENDED ->
                return VoiceEvent.SpeechEnded()
            TurnLifecycleEventKind.TURN_LIFECYCLE_EVENT_KIND_TRANSCRIPTION_FINAL ->
                return VoiceEvent.UserTranscribed(turn.transcript, isFinal = true)
            TurnLifecycleEventKind.TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_COMPLETED ->
                return VoiceEvent.AgentResponse(turn.response)
            TurnLifecycleEventKind.TURN_LIFECYCLE_EVENT_KIND_FAILED ->
                return VoiceEvent.Error(
                    turn.error?.message?.takeIf { it.isNotBlank() } ?: "Turn failed",
                    recoverable = turn.error?.recoverable ?: true,
                )
            else -> Unit
        }
    }
    vad?.let { detector ->
        if (detector.type == VADStreamEventKind.VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY) {
            return if (detector.is_speech) VoiceEvent.SpeechStarted() else VoiceEvent.SpeechEnded()
        }
    }
    state?.current?.toAgentState()?.let { return VoiceEvent.AgentStateChanged(it) }
    session_error?.let {
        return VoiceEvent.Error(it.message.ifBlank { "Voice session failed" }, it.recoverable)
    }
    return null
}

private fun PipelineState.toAgentState(): AgentState? =
    when (this) {
        PipelineState.PIPELINE_STATE_LISTENING,
        PipelineState.PIPELINE_STATE_WAITING_WAKEWORD,
        -> AgentState.LISTENING
        PipelineState.PIPELINE_STATE_THINKING,
        PipelineState.PIPELINE_STATE_PROCESSING_SPEECH,
        PipelineState.PIPELINE_STATE_GENERATING_RESPONSE,
        -> AgentState.THINKING
        PipelineState.PIPELINE_STATE_SPEAKING,
        PipelineState.PIPELINE_STATE_PLAYING_TTS,
        -> AgentState.SPEAKING
        else -> null
    }
