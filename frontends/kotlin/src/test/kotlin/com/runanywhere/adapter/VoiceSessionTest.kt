// SPDX-License-Identifier: Apache-2.0
package com.runanywhere.adapter

import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class VoiceSessionTest {

    @Test
    fun `default VoiceAgentConfig has expected models`() {
        val cfg = VoiceAgentConfig()
        assertEquals("qwen3-4b", cfg.llm)
        assertEquals("whisper-base", cfg.stt)
        assertEquals("kokoro", cfg.tts)
        assertEquals("silero-v5", cfg.vad)
        assertTrue(cfg.enableBargeIn)
    }

    @Test
    fun `session without native core yields backend-unavailable error`() = runTest {
        val session = RunAnywhere.solution(VoiceAgentConfig())
        val events  = session.run().toList()
        assertEquals(1, events.size)
        val err = events.first()
        assertTrue(err is VoiceEvent.Error, "expected Error, got $err")
        assertEquals(RunAnywhereException.BACKEND_UNAVAILABLE,
                     (err as VoiceEvent.Error).code)
    }
}
