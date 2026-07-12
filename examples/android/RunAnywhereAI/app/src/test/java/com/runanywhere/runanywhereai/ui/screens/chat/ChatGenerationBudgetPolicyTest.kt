package com.runanywhere.runanywhereai.ui.screens.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatGenerationBudgetPolicyTest {
    @Test
    fun `512 context model keeps half its window for input`() {
        val budget = ChatGenerationBudgetPolicy.resolve(
            requestedMaxTokens = 4_096,
            modelContextTokens = 512,
        )

        assertEquals(4_096, budget.requestedMaxTokens)
        assertEquals(256, budget.effectiveMaxTokens)
        assertTrue(budget.isCapped)
        assertTrue(budget.explanation("LFM").contains("preference stays saved"))
    }

    @Test
    fun `1024 context model cannot inherit a 4096 output decode`() {
        val budget = ChatGenerationBudgetPolicy.resolve(4_096, 1_024)

        assertEquals(ChatGenerationBudgetPolicy.MAX_NORMAL_OUTPUT_TOKENS, budget.effectiveMaxTokens)
        assertEquals(512, budget.effectiveMaxTokens)
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

        assertEquals(512, budget.effectiveMaxTokens)
        assertEquals(null, budget.modelContextTokens)
        assertTrue(budget.explanation("Model").contains("until it reports a context size"))
    }
}
