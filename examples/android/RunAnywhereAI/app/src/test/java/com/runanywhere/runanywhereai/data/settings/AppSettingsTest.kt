package com.runanywhere.runanywhereai.data.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AppSettingsTest {

    @Test
    fun `reasoning is off by default so small on-device models keep their budget for the answer`() {
        // Thinking-on burned Qwen3.5-0.8B's whole ~512-token output budget, leaving no room to answer.
        assertTrue(AppSettings().disableThinking)
    }

    @Test
    fun `a non-empty default system prompt is applied so small models use conversation context`() {
        // With no system prompt the small instruct models default to a defensive "I don't have
        // personal information" persona and ignore the conversation.
        assertEquals(DEFAULT_SYSTEM_PROMPT, AppSettings().systemPrompt)
        assertTrue(AppSettings().systemPrompt.isNotBlank())
        assertTrue(DEFAULT_SYSTEM_PROMPT.contains("helpful", ignoreCase = true))
    }
}
