package com.runanywhere.runanywhereai.ui.screens.chat

import ai.runanywhere.proto.v1.MessageRole
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class ChatRequestPolicyTest {
    @Test
    fun `first turn keeps the current prompt out of history`() {
        val turn = ChatRequestPolicy.snapshot("Current prompt", emptyList())
        val request = ChatRequestPolicy.buildRequest(
            turn = turn,
            options = RALLMGenerationOptions(max_output_tokens = 96),
            conversationId = "conversation-1",
            streaming = false,
        )

        // LLMGenerateRequest.prompt/.history were deleted outright; the request now
        // carries only `messages` (oldest first, ending with the turn to answer).
        assertEquals("Current prompt", request.messages.last().content)
        assertEquals(MessageRole.MESSAGE_ROLE_USER, request.messages.last().role)
        assertEquals("conversation-1", request.conversation_id)
        assertEquals(1, request.messages.size)
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
            options = RALLMGenerationOptions(max_output_tokens = 37),
            conversationId = "conversation-2",
            streaming = true,
        )

        assertEquals(37, requireNotNull(request.options).max_output_tokens)
        // LLMGenerateRequest.history was deleted outright; the prior turns are
        // prepended onto the single-message `messages` list buildRequest built
        // for the current prompt.
        assertEquals(turn.history, request.messages.dropLast(1))
        assertEquals("follow up", request.messages.last().content)
    }

    @Test
    fun `windowHistory is a no-op — no local token estimates`() {
        val turn = ChatRequestPolicy.snapshot(
            "q",
            listOf(ChatMessage("a", isUser = true), ChatMessage("b", isUser = false)),
        )
        // No app-side chars/token budget; commons owns TokenUsage. Always pass-through.
        assertEquals(turn, ChatRequestPolicy.windowHistory(turn, contextTokens = 0, outputTokens = 256, systemPrompt = null))
        assertEquals(turn, ChatRequestPolicy.windowHistory(turn, contextTokens = 512, outputTokens = 256, systemPrompt = "sys"))
    }

    @Test
    fun `windowHistory returns the turn unchanged when there is no history`() {
        val turn = ChatRequestPolicy.snapshot("hello", emptyList())
        assertEquals(turn, ChatRequestPolicy.windowHistory(turn, contextTokens = 512, outputTokens = 256, systemPrompt = "sys"))
    }

    @Test
    fun `windowHistory keeps the full history without local trimming`() {
        val turn = ChatRequestPolicy.snapshot(
            "what is my name?",
            listOf(
                ChatMessage("my name is Bob", isUser = true),
                ChatMessage("Hi Bob!", isUser = false),
                ChatMessage("i like blue", isUser = true),
                ChatMessage("Blue is a nice colour.", isUser = false),
            ),
        )
        val windowed = ChatRequestPolicy.windowHistory(turn, contextTokens = 1024, outputTokens = 512, systemPrompt = "You are helpful.")
        assertEquals(turn.history, windowed.history)
        assertEquals(turn.prompt, windowed.prompt)
    }

    @Test
    fun `windowHistory does not invent token budgets on a small context`() {
        val history = (1..16).map { i ->
            ChatMessage(
                text = "turn $i: a reasonably long conversational message with enough words to matter",
                isUser = i % 2 == 1,
            )
        }
        val turn = ChatRequestPolicy.snapshot("what did i first say?", history)
        val windowed = ChatRequestPolicy.windowHistory(turn, contextTokens = 512, outputTokens = 256, systemPrompt = "You are helpful.")

        assertEquals(turn.history, windowed.history)
        assertEquals(turn.prompt, windowed.prompt)
    }

    @Test
    fun `stray tool-call markup never reaches the chat bubble on the standard route`() {
        // Verbatim from an LFM2.5-2.6B reply to a plain greeting, with no tools registered.
        val raw = """<|tool_call_start|>[ask_user("What would you like to do today, Aman? """ +
            """I'm here to help with any questions or tasks you have.")]<|tool_call_end|>"""

        val visible = ChatToolResultNormalizer.stripStrayToolCall(raw)

        assertFalse("tool markers must not survive", visible.contains("tool_call_start"))
        assertFalse("tool markers must not survive", visible.contains("tool_call_end"))
        // The call's string literal is the model's intended sentence — surface it rather than a blank bubble.
        assertEquals(
            "What would you like to do today, Aman? I'm here to help with any questions or tasks you have.",
            visible,
        )
    }

    @Test
    fun `stray tool-call salvage also covers the default tool_call form`() {
        // Same shape as the LFM2.5 case above, in the DEFAULT `<tool_call>` syntax that
        // `strayToolCall` also matches. The call body lands in the regex's second group,
        // so reading only the first left the bubble blank.
        val raw = """<tool_call>[ask_user("What would you like to do today, Aman?")]</tool_call>"""

        val visible = ChatToolResultNormalizer.stripStrayToolCall(raw)

        assertFalse("tool markers must not survive", visible.contains("tool_call"))
        assertEquals("What would you like to do today, Aman?", visible)
    }

    @Test
    fun `stray tool-call stripping keeps surrounding prose and leaves clean replies untouched`() {
        val mixed = "Sure, here you go.<|tool_call_start|>[noop()]<|tool_call_end|>"
        assertEquals("Sure, here you go.", ChatToolResultNormalizer.stripStrayToolCall(mixed))

        val clean = "Your name is Aman. I have that from our conversation."
        assertEquals(clean, ChatToolResultNormalizer.stripStrayToolCall(clean))
    }

    @Test
    fun `windowHistory preserves short facts even when a later reply is huge`() {
        val fact = ChatMessage("My name is Aman and I love pizza", isUser = true)
        val hugeReply = ChatMessage("word ".repeat(200), isUser = false)
        val turn = ChatRequestPolicy.snapshot("what is my name and which food do i love?", listOf(fact, hugeReply))

        val windowed = ChatRequestPolicy.windowHistory(
            turn, contextTokens = 512, outputTokens = 256, systemPrompt = "You are a helpful assistant.",
        )

        // No local estimate trimming — full history is forwarded to commons.
        assertEquals(turn.history, windowed.history)
        assertEquals(2, windowed.history.size)
    }

    @Test
    fun `windowHistory never drops history for a huge current prompt`() {
        val hugePrompt = "word ".repeat(400)
        val turn = ChatRequestPolicy.snapshot(
            hugePrompt,
            listOf(ChatMessage("older", isUser = true), ChatMessage("older reply", isUser = false)),
        )
        val windowed = ChatRequestPolicy.windowHistory(turn, contextTokens = 512, outputTokens = 128, systemPrompt = "sys")
        assertEquals(turn.history, windowed.history)
        assertEquals(hugePrompt, windowed.prompt)
    }
}
