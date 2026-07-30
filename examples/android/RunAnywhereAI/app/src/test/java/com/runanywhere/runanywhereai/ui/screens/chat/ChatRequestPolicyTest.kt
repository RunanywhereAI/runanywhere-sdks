package com.runanywhere.runanywhereai.ui.screens.chat

import com.runanywhere.sdk.public.api.ChatRole
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatRequestPolicyTest {
    @Test
    fun `first turn keeps the current prompt out of history`() {
        val turn = ChatRequestPolicy.snapshot("Current prompt", emptyList())

        assertEquals("Current prompt", turn.prompt)
        assertTrue(turn.history.isEmpty())
        assertEquals(
            listOf(ChatRole.USER to "Current prompt"),
            ChatRequestPolicy.toMessages(turn).map { it.role to it.content },
        )
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
                ChatRole.USER to "first question",
                ChatRole.ASSISTANT to "first answer",
            ),
            turn.history.map { it.role to it.content },
        )
        assertFalse(turn.history.any { it.content == turn.prompt })
    }

    @Test
    fun `the transcript is prior history followed by the current prompt`() {
        val turn = ChatRequestPolicy.snapshot(
            prompt = "follow up",
            messages = listOf(ChatMessage(text = "prior", isUser = true)),
        )
        val messages = ChatRequestPolicy.toMessages(turn)

        assertEquals(turn.history, messages.dropLast(1))
        assertEquals(ChatRole.USER, messages.last().role)
        assertEquals("follow up", messages.last().content)
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
