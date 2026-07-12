package com.runanywhere.runanywhereai.ui.screens.chat

import ai.runanywhere.proto.v1.MessageRole
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatRequestPolicyTest {
    @Test
    fun `first turn keeps the current prompt out of history`() {
        val turn = ChatRequestPolicy.snapshot("Current prompt", emptyList())
        val request = ChatRequestPolicy.buildRequest(
            turn = turn,
            options = RALLMGenerationOptions(max_tokens = 96),
            conversationId = "conversation-1",
            streaming = false,
        )

        assertEquals("Current prompt", request.prompt)
        assertEquals("conversation-1", request.conversation_id)
        assertTrue(request.history.isEmpty())
        assertFalse(requireNotNull(request.options).streaming_enabled)
    }

    @Test
    fun `history preserves chronological roles and excludes blank placeholders`() {
        val turn = ChatRequestPolicy.snapshot(
            prompt = "follow up",
            messages = listOf(
                ChatMessage(text = "first question", isUser = true),
                ChatMessage(text = "first answer", isUser = false),
                ChatMessage(text = "", isUser = false),
                ChatMessage(text = "   ", isUser = true),
            ),
        )

        assertEquals(
            listOf(
                MessageRole.MESSAGE_ROLE_USER to "first question",
                MessageRole.MESSAGE_ROLE_ASSISTANT to "first answer",
            ),
            turn.history.map { it.role to it.content },
        )
        assertFalse(turn.history.any { it.content == turn.prompt })
    }

    @Test
    fun `stream request preserves history budget and canonical streaming flag`() {
        val turn = ChatRequestPolicy.snapshot(
            prompt = "follow up",
            messages = listOf(ChatMessage(text = "prior", isUser = true)),
        )
        val request = ChatRequestPolicy.buildRequest(
            turn = turn,
            options = RALLMGenerationOptions(max_tokens = 37),
            conversationId = "conversation-2",
            streaming = true,
        )

        assertEquals(37, requireNotNull(request.options).max_tokens)
        assertEquals(turn.history, request.history)
        assertTrue(requireNotNull(request.options).streaming_enabled)
    }
}
