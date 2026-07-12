package com.runanywhere.runanywhereai.ui.screens.rag

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RagGenerationPolicyTest {
    @Test
    fun `production options are concise deterministic and disable thinking`() {
        val options = RagGenerationPolicy.options("What is the total?", multiQueryEnabled = true)

        assertEquals(192, options.max_tokens)
        assertEquals(0.0f, options.temperature)
        assertEquals(1.0f, options.top_p)
        assertEquals(0, options.top_k)
        assertEquals("What is the total?", options.question)
        assertTrue(options.disable_thinking)
        assertTrue(options.enable_multi_query)
        assertFalse(options.stream)
        assertTrue(options.system_prompt.orEmpty().contains("at most three concise sentences"))
    }

    @Test
    fun `normalizer strips complete and unclosed thinking while preserving answer`() {
        assertEquals(
            "The invoice total is $1,284.",
            RagAnswerNormalizer.visibleAnswer(
                "<think>private chain</think>The invoice total is $1,284.",
            ),
        )
        assertEquals(
            "The invoice total is $1,284.",
            RagAnswerNormalizer.visibleAnswer(
                "The invoice total is $1,284. <thinking>unfinished private chain",
            ),
        )
        assertEquals("", RagAnswerNormalizer.visibleAnswer("<THINK>Thinking Process only"))
    }

    @Test
    fun `normalizer tolerates malformed tag remnants without changing a plain answer`() {
        assertEquals(
            "The retained answer.",
            RagAnswerNormalizer.visibleAnswer("< THINK >hidden< / THINK >The retained answer."),
        )
        assertEquals(
            "The retained answer.",
            RagAnswerNormalizer.visibleAnswer("The retained answer. <thinking"),
        )
        assertEquals("The retained answer.", RagAnswerNormalizer.visibleAnswer("The retained answer."))
    }

    @Test
    fun `query version rejects results after stop replacement or corpus reset`() {
        val request = RagQueryVersion(query = 7, corpus = 3)

        assertTrue(request.isCurrent(currentQuery = 7, currentCorpus = 3))
        assertFalse(request.isCurrent(currentQuery = 8, currentCorpus = 3))
        assertFalse(request.isCurrent(currentQuery = 7, currentCorpus = 4))
    }

    @Test
    fun `sanitized fallback still retains retrieval sources and timing`() {
        val sources = listOf(RagSource(text = "Invoice total: $1,284", score = 0.91f, document = "invoice.pdf"))

        val message = buildRagAnswerMessage(
            rawAnswer = "<think>private reasoning only",
            sources = sources,
            elapsedMs = 1_234,
        )

        assertFalse(message.isUser)
        assertEquals("I couldn't produce a concise answer. Try asking more specifically.", message.text)
        assertEquals(sources, message.sources)
        assertEquals(1_234, message.elapsedMs)
    }
}
