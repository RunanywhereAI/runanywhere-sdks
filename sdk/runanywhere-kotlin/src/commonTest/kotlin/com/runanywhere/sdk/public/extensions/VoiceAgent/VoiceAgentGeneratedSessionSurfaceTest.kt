package com.runanywhere.sdk.public.extensions.VoiceAgent

import ai.runanywhere.proto.v1.AgentResponseStartedEvent
import ai.runanywhere.proto.v1.AudioEncoding
import ai.runanywhere.proto.v1.AudioLevelEvent
import ai.runanywhere.proto.v1.ErrorCode
import ai.runanywhere.proto.v1.PipelineState
import ai.runanywhere.proto.v1.SessionStartedEvent
import ai.runanywhere.proto.v1.StateChangeEvent
import ai.runanywhere.proto.v1.TurnLifecycleEvent
import ai.runanywhere.proto.v1.TurnLifecycleEventKind
import ai.runanywhere.proto.v1.VoiceAgentTurnRequest
import ai.runanywhere.proto.v1.VoiceEvent
import ai.runanywhere.proto.v1.VoiceSessionConfig
import ai.runanywhere.proto.v1.VoiceSessionError
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.processVoiceTurn
import com.runanywhere.sdk.public.extensions.streamVoiceAgent
import com.runanywhere.sdk.public.extensions.toVoiceAgentTurnRequest
import kotlinx.coroutines.flow.Flow
import okio.ByteString.Companion.toByteString
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

    @Test
    fun `audio-only voice turn request preserves audio fields`() {
        val request =
            byteArrayOf(1, 2, 3).toVoiceAgentTurnRequest(
                sampleRateHz = 16000,
                channels = 1,
                encoding = AudioEncoding.AUDIO_ENCODING_PCM_S16_LE,
            )

        assertEquals(byteArrayOf(1, 2, 3).toByteString(), request.audio_data)
        assertEquals(16000, request.sample_rate_hz)
        assertEquals(1, request.channels)
        assertEquals(AudioEncoding.AUDIO_ENCODING_PCM_S16_LE, request.encoding)
    }

    @Test
    fun `voice agent turn request accepts full session fields`() {
        val request =
            VoiceAgentTurnRequest(
                audio_data = byteArrayOf(1).toByteString(),
                session_config = VoiceSessionConfig(continuous_mode = true),
                metadata = mapOf("source" to "test"),
            )

        // Wave D-7 / KOT-11: Kotlin forwards the full VoiceAgentTurnRequest
        // bytes to the native session ABI — no field rejection.
        assertEquals("test", request.metadata["source"])
    }
}

@Suppress("unused")
private fun voiceAgentStreamSurface(): Flow<VoiceEvent> =
    RunAnywhere.streamVoiceAgent()

@Suppress("unused")
private suspend fun voiceAgentTurnSurface() =
    RunAnywhere.processVoiceTurn(VoiceAgentTurnRequest(audio_data = byteArrayOf(1).toByteString()))
