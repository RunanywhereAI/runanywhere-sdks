package com.runanywhere.sdk.public.extensions.Solutions

import ai.runanywhere.proto.v1.SolutionConfig
import ai.runanywhere.proto.v1.SolutionType
import ai.runanywhere.proto.v1.VoiceAgentConfig
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.SolutionHandle
import com.runanywhere.sdk.public.extensions.Solutions
import com.runanywhere.sdk.public.extensions.solutions
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Generated Solutions public-surface coverage — mirrors Swift
 * SolutionsSurfaceTests.swift. The commons layer is covered by
 * test_solution_runner.cpp; this pins the SDK-layer proto round-trip plus the
 * `RunAnywhere.solutions` capability shape so a drift in the generated types or
 * the public `run` overloads fails at unit-test time.
 */
class SolutionsGeneratedSurfaceTest {
    @Test
    fun `generated SolutionConfig carries voice agent oneof fields`() {
        val config =
            SolutionConfig(
                voice_agent =
                    VoiceAgentConfig(
                        llm_model_id = "qwen3-4b-q4_k_m",
                        stt_model_id = "whisper-base",
                        tts_model_id = "kokoro",
                        vad_model_id = "silero-v5",
                        sample_rate_hz = 16000,
                        chunk_ms = 20,
                        max_context_tokens = 4096,
                        type_kind = SolutionType.SOLUTION_TYPE_VOICE_AGENT,
                    ),
            )

        val voiceAgent = assertNotNull(config.voice_agent)
        assertEquals("qwen3-4b-q4_k_m", voiceAgent.llm_model_id)
        assertEquals("whisper-base", voiceAgent.stt_model_id)
        assertEquals("kokoro", voiceAgent.tts_model_id)
        assertEquals("silero-v5", voiceAgent.vad_model_id)
        assertEquals(16000, voiceAgent.sample_rate_hz)
        assertEquals(20, voiceAgent.chunk_ms)
        assertEquals(4096, voiceAgent.max_context_tokens)
        assertEquals(SolutionType.SOLUTION_TYPE_VOICE_AGENT, voiceAgent.type_kind)
    }

    @Test
    fun `generated SolutionConfig round-trips through proto bytes`() {
        val config =
            SolutionConfig(
                voice_agent = VoiceAgentConfig(llm_model_id = "qwen3-4b-q4_k_m"),
            )

        val bytes = config.encode()
        assertTrue(bytes.isNotEmpty())
        assertEquals(config, SolutionConfig.ADAPTER.decode(bytes))
    }

    @Test
    fun `RunAnywhere solutions capability exposes generated run overloads`() {
        val capability: Solutions = RunAnywhere.solutions
        assertNotNull(capability)

        val runBytes: suspend (ByteArray) -> SolutionHandle = capability::run
        val runConfig: suspend (SolutionConfig) -> SolutionHandle = capability::run
        val runYaml: suspend (String) -> SolutionHandle = capability::run

        @Suppress("UNUSED_EXPRESSION")
        listOf(runBytes, runConfig, runYaml)
    }
}
