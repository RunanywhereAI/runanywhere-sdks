/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Small generated-event helpers for voice session UIs. These helpers map
 * VoiceEvent oneof arms to generated proto state/error values only; they do
 * not introduce another public voice-session DTO.
 *
 * idl/voice_events.proto reshaped VoiceEvent's `payload` oneof outright:
 * `session_started`/`session_stopped`/`agent_response_started`/
 * `agent_response_completed`/`speech_turn_detection`/`audio_level` are all
 * gone with no direct replacement arm. Session start/stop are now
 * `StateChangeEvent` (`state`) transitions; agent-response start/complete
 * and user-speech start/end are `TurnLifecycleEventKind` values on
 * `turn_lifecycle`, not separate oneof arms. There is no audio-level event
 * any more -- nothing in commons populates one (see the SDK's own capability
 * notes): `speechDetectedOrNull()` now derives speech activity from `vad`
 * (`VADEvent.is_speech`) and `turn_lifecycle` only.
 */

package com.runanywhere.sdk.public.extensions.VoiceAgent

import ai.runanywhere.proto.v1.PipelineState
import ai.runanywhere.proto.v1.TurnLifecycleEventKind
import ai.runanywhere.proto.v1.VADStreamEventKind
import com.runanywhere.sdk.public.types.RAVoiceEvent

internal fun RAVoiceEvent.pipelineStateOrNull(): PipelineState? {
    state?.current?.takeUnless { it == PipelineState.PIPELINE_STATE_UNSPECIFIED }?.let { return it }

    return when {
        session_error != null -> PipelineState.PIPELINE_STATE_ERROR
        audio != null -> PipelineState.PIPELINE_STATE_SPEAKING
        turn_lifecycle != null -> turn_lifecycle!!.kind.toPipelineStateOrNull()
        else -> null
    }
}

internal fun RAVoiceEvent.speechDetectedOrNull(): Boolean? =
    when {
        // VADEvent.type uses VADStreamEventKind; speech start/end
        // both ride SPEECH_ACTIVITY with direction on the is_speech bool.
        vad?.type == VADStreamEventKind.VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY -> vad!!.is_speech
        turn_lifecycle?.kind == TurnLifecycleEventKind.TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_STARTED -> true
        turn_lifecycle?.kind == TurnLifecycleEventKind.TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_ENDED -> false
        else -> null
    }

internal fun RAVoiceEvent.errorMessageOrNull(): String? =
    session_error?.message?.takeIf { it.isNotBlank() }

private fun TurnLifecycleEventKind.toPipelineStateOrNull(): PipelineState? =
    when (this) {
        TurnLifecycleEventKind.TURN_LIFECYCLE_EVENT_KIND_STARTED,
        TurnLifecycleEventKind.TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_STARTED,
        -> PipelineState.PIPELINE_STATE_LISTENING
        TurnLifecycleEventKind.TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_ENDED,
        TurnLifecycleEventKind.TURN_LIFECYCLE_EVENT_KIND_TRANSCRIPTION_FINAL,
        -> PipelineState.PIPELINE_STATE_THINKING
        TurnLifecycleEventKind.TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_STARTED ->
            PipelineState.PIPELINE_STATE_GENERATING_RESPONSE
        TurnLifecycleEventKind.TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_COMPLETED ->
            PipelineState.PIPELINE_STATE_SPEAKING
        TurnLifecycleEventKind.TURN_LIFECYCLE_EVENT_KIND_COMPLETED,
        TurnLifecycleEventKind.TURN_LIFECYCLE_EVENT_KIND_CANCELLED,
        -> PipelineState.PIPELINE_STATE_STOPPED
        TurnLifecycleEventKind.TURN_LIFECYCLE_EVENT_KIND_FAILED -> PipelineState.PIPELINE_STATE_ERROR
        else -> null
    }
