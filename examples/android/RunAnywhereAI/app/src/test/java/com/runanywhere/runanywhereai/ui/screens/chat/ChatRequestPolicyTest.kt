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

    @Test
    fun `windowHistory is a no-op when the context size is unknown`() {
        val turn = ChatRequestPolicy.snapshot(
            "q",
            listOf(ChatMessage("a", isUser = true), ChatMessage("b", isUser = false)),
        )
        // 0 context (model never reported one) -> never trim; behave exactly like today.
        assertEquals(turn, ChatRequestPolicy.windowHistory(turn, contextTokens = 0, outputTokens = 256, systemPrompt = null))
    }

    @Test
    fun `windowHistory returns the turn unchanged when there is no history`() {
        val turn = ChatRequestPolicy.snapshot("hello", emptyList())
        assertEquals(turn, ChatRequestPolicy.windowHistory(turn, contextTokens = 512, outputTokens = 256, systemPrompt = "sys"))
    }

    @Test
    fun `windowHistory keeps the full history when it fits the context`() {
        val turn = ChatRequestPolicy.snapshot(
            "what is my name?",
            listOf(
                ChatMessage("my name is Bob", isUser = true),
                ChatMessage("Hi Bob!", isUser = false),
                ChatMessage("i like blue", isUser = true),
                ChatMessage("Blue is a nice colour.", isUser = false),
            ),
        )
        // Qwen3.5-0.8B: 1024 ctx, 512 output budget -> ample room for a short chat, nothing trimmed.
        val windowed = ChatRequestPolicy.windowHistory(turn, contextTokens = 1024, outputTokens = 512, systemPrompt = "You are helpful.")
        assertEquals(turn.history, windowed.history)
        assertEquals(turn.prompt, windowed.prompt)
    }

    @Test
    fun `windowHistory trims the oldest turns to fit a small context, keeping the recent suffix in order`() {
        val history = (1..16).map { i ->
            ChatMessage(
                text = "turn $i: a reasonably long conversational message with enough words to matter",
                isUser = i % 2 == 1,
            )
        }
        val turn = ChatRequestPolicy.snapshot("what did i first say?", history)
        // Llama-3.2-1B on v79: 512 ctx, ~256 output budget -> only a few recent turns fit.
        val windowed = ChatRequestPolicy.windowHistory(turn, contextTokens = 512, outputTokens = 256, systemPrompt = "You are helpful.")

        assertTrue("expected history to be trimmed", windowed.history.size < turn.history.size)
        assertTrue("expected at least one kept turn", windowed.history.isNotEmpty())
        // Kept turns are the most-recent contiguous suffix, never reordered and never pulled from the middle.
        assertEquals(turn.history.takeLast(windowed.history.size), windowed.history)
        assertEquals(turn.prompt, windowed.prompt)
    }

    @Test
    fun `windowHistory drops all history when the current prompt alone fills the context`() {
        val hugePrompt = "word ".repeat(400) // ~2000 chars -> far exceeds a 512-token window on its own
        val turn = ChatRequestPolicy.snapshot(
            hugePrompt,
            listOf(ChatMessage("older", isUser = true), ChatMessage("older reply", isUser = false)),
        )
        val windowed = ChatRequestPolicy.windowHistory(turn, contextTokens = 512, outputTokens = 128, systemPrompt = "sys")
        assertTrue(windowed.history.isEmpty())
        assertEquals(hugePrompt, windowed.prompt) // the current turn is never dropped
    }
}
