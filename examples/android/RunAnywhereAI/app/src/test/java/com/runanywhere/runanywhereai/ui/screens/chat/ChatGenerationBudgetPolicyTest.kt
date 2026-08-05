package com.runanywhere.runanywhereai.ui.screens.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatGenerationBudgetPolicyTest {
    @Test
    fun `context-bound 512 model reserves half its window for input`() {
        val budget = ChatGenerationBudgetPolicy.resolve(
            requestedMaxTokens = 4_096,
            modelContextTokens = 512,
        )

        assertEquals(4_096, budget.requestedMaxTokens)
        assertEquals(256, budget.effectiveMaxTokens) // 512 / 2
        assertTrue(budget.isCapped)
        assertTrue(budget.explanation("LFM").contains("preference stays saved"))
    }

    @Test
    fun `sliding-window model is not bounded by its small context`() {
        // QHexRT NPU (KV ring) keeps generating coherently past its context, so output caps at the global
        // ceiling instead of the context window.
        val budget = ChatGenerationBudgetPolicy.resolve(
            requestedMaxTokens = 4_096,
            modelContextTokens = 512,
            slidingWindow = true,
        )

        assertEquals(ChatGenerationBudgetPolicy.MAX_NORMAL_OUTPUT_TOKENS, budget.effectiveMaxTokens)
        assertEquals(1_024, budget.effectiveMaxTokens)
        assertTrue(budget.isCapped)
    }

    @Test
    fun `context-bound 1024 model reserves half its window`() {
        val budget = ChatGenerationBudgetPolicy.resolve(4_096, 1_024)

        assertEquals(512, budget.effectiveMaxTokens) // 1024 / 2
    }

    @Test
    fun `smaller user preference is preserved on a large context model`() {
        val budget = ChatGenerationBudgetPolicy.resolve(256, 8_192)

        assertEquals(256, budget.effectiveMaxTokens)
        assertFalse(budget.isCapped)
    }

    @Test
    fun `unknown context fails to the bounded normal chat maximum`() {
        val budget = ChatGenerationBudgetPolicy.resolve(4_096, 0)

        assertEquals(ChatGenerationBudgetPolicy.MAX_NORMAL_OUTPUT_TOKENS, budget.effectiveMaxTokens)
        assertEquals(null, budget.modelContextTokens)
        assertTrue(budget.explanation("Model").contains("until it reports a context size"))
    }
}
