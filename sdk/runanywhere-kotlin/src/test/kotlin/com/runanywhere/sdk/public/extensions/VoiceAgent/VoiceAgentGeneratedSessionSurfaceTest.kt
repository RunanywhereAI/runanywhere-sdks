package com.runanywhere.sdk.public.extensions.VoiceAgent

import ai.runanywhere.proto.v1.AgentResponseStartedEvent
import ai.runanywhere.proto.v1.AudioLevelEvent
import ai.runanywhere.proto.v1.ErrorCode
import ai.runanywhere.proto.v1.PipelineState
import ai.runanywhere.proto.v1.SessionStartedEvent
import ai.runanywhere.proto.v1.StateChangeEvent
import ai.runanywhere.proto.v1.TurnLifecycleEvent
import ai.runanywhere.proto.v1.TurnLifecycleEventKind
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
        assertEquals(
            PipelineState.PIPELINE_STATE_LISTENING,
            VoiceEvent(session_started = SessionStartedEvent(session_id = "s1")).pipelineStateOrNull(),
        )
        assertEquals(
            PipelineState.PIPELINE_STATE_GENERATING_RESPONSE,
            VoiceEvent(agent_response_started = AgentResponseStartedEvent(turn_id = "t1")).pipelineStateOrNull(),
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
    fun `generated audio level event maps to speech activity`() {
        assertFalse(VoiceEvent(audio_level = AudioLevelEvent(rms = 0.01f)).speechDetectedOrNull()!!)
        assertEquals(true, VoiceEvent(audio_level = AudioLevelEvent(rms = 0.2f, is_speech = true)).speechDetectedOrNull())
    }
}

@Suppress("unused")
private fun voiceAgentStreamSurface(): Flow<VoiceEvent> =
    RunAnywhere.streamVoiceAgent()
