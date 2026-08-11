package com.runanywhere.runanywhereai.ui.screens.rag

import com.runanywhere.sdk.public.api.ReasoningMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RagGenerationPolicyTest {
    @Test
    fun `production options are concise deterministic and disable thinking`() {
        val options = RagGenerationPolicy.options()

        assertEquals(192, options.maxOutputTokens)
        assertEquals(0.0f, options.temperature)
        assertEquals(1.0f, options.topP)
        assertEquals(ReasoningMode.OFF, options.reasoning?.mode)
        assertTrue(options.systemPrompt.orEmpty().contains("at most three concise sentences"))
    }

    @Test
    fun `query version rejects results after stop replacement or corpus reset`() {
        val request = RagQueryVersion(query = 7, corpus = 3)

        assertTrue(request.isCurrent(currentQuery = 7, currentCorpus = 3))
        assertFalse(request.isCurrent(currentQuery = 8, currentCorpus = 3))
        assertFalse(request.isCurrent(currentQuery = 7, currentCorpus = 4))
    }

    @Test
    fun `blank commons answer keeps retrieval sources and timing with UI placeholder`() {
        val sources = listOf(RagSource(text = "Invoice total: $1,284", score = 0.91f, document = "invoice.pdf"))

        val message = buildRagAnswerMessage(
            rawAnswer = "   ",
            sources = sources,
            elapsedMs = 1_234,
        )

        assertFalse(message.isUser)
        assertEquals("I couldn't produce a concise answer. Try asking more specifically.", message.text)
        assertEquals(sources, message.sources)
        assertEquals(1_234, message.elapsedMs)
    }

    @Test
    fun `commons answer channel is shown without app-side tag parsing`() {
        val message = buildRagAnswerMessage(
            rawAnswer = "The invoice total is $1,284.",
            sources = emptyList(),
            elapsedMs = 10,
        )
        assertEquals("The invoice total is $1,284.", message.text)
    }
}
