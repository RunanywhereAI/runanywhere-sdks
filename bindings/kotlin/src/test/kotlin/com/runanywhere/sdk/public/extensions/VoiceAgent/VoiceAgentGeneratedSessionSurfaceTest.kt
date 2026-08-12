package com.runanywhere.sdk.public.extensions.VoiceAgent

import ai.runanywhere.proto.v1.ErrorCode
import ai.runanywhere.proto.v1.PipelineState
import ai.runanywhere.proto.v1.StateChangeEvent
import ai.runanywhere.proto.v1.TurnLifecycleEvent
import ai.runanywhere.proto.v1.TurnLifecycleEventKind
import ai.runanywhere.proto.v1.VADEvent
import ai.runanywhere.proto.v1.VADStreamEventKind
import ai.runanywhere.proto.v1.VoiceEvent
import ai.runanywhere.proto.v1.VoiceSessionError
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.streamVoiceAgent
import kotlinx.coroutines.flow.Flow
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class VoiceAgentGeneratedSessionSurfaceTest {
    @Test
    fun `generated voice event lifecycle arms map to generated pipeline states`() {
        // session_started/agent_response_started were deleted outright
        // (idl/voice_events.proto): session start/stop are now
        // StateChangeEvent transitions, and agent-response start/complete
        // are TurnLifecycleEventKind values on turn_lifecycle.
        assertEquals(
            PipelineState.PIPELINE_STATE_LISTENING,
            VoiceEvent(
                turn_lifecycle =
                    TurnLifecycleEvent(
                        kind = TurnLifecycleEventKind.TURN_LIFECYCLE_EVENT_KIND_STARTED,
                    ),
            ).pipelineStateOrNull(),
        )
        assertEquals(
            PipelineState.PIPELINE_STATE_GENERATING_RESPONSE,
            VoiceEvent(
                turn_lifecycle =
                    TurnLifecycleEvent(
                        kind = TurnLifecycleEventKind.TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_STARTED,
                    ),
            ).pipelineStateOrNull(),
        )
        assertEquals(
            PipelineState.PIPELINE_STATE_STOPPED,
            VoiceEvent(
                turn_lifecycle =
                    TurnLifecycleEvent(
                        kind = TurnLifecycleEventKind.TURN_LIFECYCLE_EVENT_KIND_COMPLETED,
                    ),
            ).pipelineStateOrNull(),
        )
    }

    @Test
    fun `explicit generated state change maps directly to pipeline state`() {
        val event =
            VoiceEvent(
                state =
                    StateChangeEvent(
                        current = PipelineState.PIPELINE_STATE_PLAYING_TTS,
                    ),
            )

        assertEquals(PipelineState.PIPELINE_STATE_PLAYING_TTS, event.pipelineStateOrNull())
    }

    @Test
    fun `generated session error maps to error message and state`() {
        val event =
            VoiceEvent(
                session_error =
                    VoiceSessionError(
                        code = ErrorCode.ERROR_CODE_COMPONENT_NOT_READY,
                        message = "native session feed unavailable",
                    ),
            )

        assertEquals(PipelineState.PIPELINE_STATE_ERROR, event.pipelineStateOrNull())
        assertEquals("native session feed unavailable", event.errorMessageOrNull())
    }

    @Test
    fun `generated vad event maps to speech activity`() {
        // AudioLevelEvent was deleted outright (idl/voice_events.proto) with
        // no replacement -- nothing in commons emits an audio-level event.
        // Speech activity now derives from VADEvent.is_speech on the
        // SPEECH_ACTIVITY stream-event kind.
        assertFalse(
            VoiceEvent(
                vad =
                    VADEvent(
                        type = VADStreamEventKind.VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY,
                        is_speech = false,
                    ),
            ).speechDetectedOrNull()!!,
        )
        assertEquals(
            true,
            VoiceEvent(
                vad =
                    VADEvent(
                        type = VADStreamEventKind.VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY,
                        is_speech = true,
                    ),
            ).speechDetectedOrNull(),
        )
    }
}

@Suppress("unused")
private fun voiceAgentStreamSurface(): Flow<VoiceEvent> =
    RunAnywhere.streamVoiceAgent()
