package com.runanywhere.runanywhereai.data.conversation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SmartTitlePolicyTest {
    @Test
    fun `title generation always disables thinking and stays tightly bounded`() {
        val options = SmartTitlePolicy.generationOptions("title only")

        assertEquals(32, options.max_tokens)
        assertTrue(options.disable_thinking)
        assertEquals(8_000L, SmartTitlePolicy.TIMEOUT_MILLIS)
    }

    @Test
    fun `persisted attempt blocks retries including failed attempts`() {
        assertTrue(SmartTitlePolicy.canAttempt(conversation()))
        assertFalse(SmartTitlePolicy.canAttempt(conversation(attempted = true)))
    }

    @Test
    fun `manual title is never replaced`() {
        assertFalse(SmartTitlePolicy.canAttempt(conversation(title = "Manual title")))
        assertFalse(SmartTitlePolicy.titleCanBeReplaced(conversation(title = "Manual title", attempted = true)))
    }

    @Test
    fun `thinking markup cannot become a title`() {
        assertEquals(
            "Useful Kotlin Tips",
            SmartTitlePolicy.normalizedTitle("<think>private plan</think>\nUseful Kotlin Tips"),
        )
        assertNull(SmartTitlePolicy.normalizedTitle("<think>still reasoning at token cap"))
    }

    @Test
    fun `process lifecycle permits exactly one attempt after success failure or cancellation`() {
        val lifecycle = SmartTitleLifecycle()

        assertTrue(lifecycle.tryStart("conversation-a"))
        lifecycle.finish("conversation-a")
        assertTrue(lifecycle.hasAttempted("conversation-a"))
        assertFalse(lifecycle.tryStart("conversation-a"))

        assertTrue(lifecycle.tryStart("conversation-b"))
        assertFalse(lifecycle.tryStart("conversation-c"))
        lifecycle.finish("conversation-b")
        assertTrue(lifecycle.tryStart("conversation-c"))
    }

    private fun conversation(
        title: String = "How do coroutines work?",
        attempted: Boolean = false,
    ): StoredConversation = StoredConversation(
        id = "conversation-a",
        title = title,
        createdAt = 1,
        updatedAt = 1,
        messages = listOf(StoredMessage(text = "How do coroutines work?", isUser = true)),
        smartTitleAttempted = attempted,
    )
}
