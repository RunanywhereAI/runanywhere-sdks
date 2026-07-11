package com.runanywhere.runanywhereai.ui.screens.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class ChatGenerationCleanupPolicyTest {
    @Test
    fun `stop finalizes an empty assistant placeholder`() {
        val stopped = ChatGenerationCleanupPolicy.afterStop(ChatMessage(text = "", isUser = false))

        assertEquals("Stopped.", stopped.text)
    }

    @Test
    fun `stop finalizes a visible tool progress row`() {
        val stopped = ChatGenerationCleanupPolicy.afterStop(
            ChatMessage(
                text = ToolCallingExecutionPolicy.PROGRESS_MESSAGE,
                isUser = false,
            ),
        )

        assertEquals("Stopped.", stopped.text)
    }

    @Test
    fun `stop preserves a partial assistant response`() {
        val partial = ChatMessage(text = "A partial answer", isUser = false)

        assertEquals(partial, ChatGenerationCleanupPolicy.afterStop(partial))
    }

    @Test
    fun `stop terminalizes a thinking-only reply without discarding its reasoning`() {
        val reply = ChatMessage(text = "", isUser = false, thinking = "partial reasoning")

        val stopped = ChatGenerationCleanupPolicy.afterStop(reply)

        assertEquals("Stopped.", stopped.text)
        assertEquals("partial reasoning", stopped.thinking)
    }

    @Test
    fun `stop strips an unterminated raw thinking block and terminalizes the row`() {
        val stopped = ChatGenerationCleanupPolicy.afterStop(
            ChatMessage(text = "<think>private partial reasoning", isUser = false),
        )

        assertEquals("Stopped.", stopped.text)
        assertEquals("private partial reasoning", stopped.thinking)
    }
}
