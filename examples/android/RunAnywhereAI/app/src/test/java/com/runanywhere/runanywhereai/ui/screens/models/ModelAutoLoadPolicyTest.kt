package com.runanywhere.runanywhereai.ui.screens.models

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ModelAutoLoadPolicyTest {

    @Test
    fun `prefers Qwen3_5 over other ready models`() {
        val ready = listOf("lfm2_5_230m", "lfm2_5_350m", "qwen3_5_0_8b")
        assertEquals("qwen3_5_0_8b", ModelAutoLoadPolicy.preferredCandidateId(ready))
    }

    @Test
    fun `degrades to the next preference when the top pick is not downloaded`() {
        val ready = listOf("lfm2_5_230m", "lfm2_5_350m") // no qwen3_5
        assertEquals("lfm2_5_350m", ModelAutoLoadPolicy.preferredCandidateId(ready))
    }

    @Test
    fun `matches an arch-suffixed variant id`() {
        val ready = listOf("lfm2_5_230m", "qwen3_5_0_8b_v79")
        assertEquals("qwen3_5_0_8b_v79", ModelAutoLoadPolicy.preferredCandidateId(ready))
    }

    @Test
    fun `does not match a preference as an arbitrary substring of another id`() {
        // "myqwen3_5_0_8b_custom" must NOT satisfy the "qwen3_5_0_8b" preference.
        val ready = listOf("myqwen3_5_0_8b_custom", "lfm2_5_350m")
        assertEquals("lfm2_5_350m", ModelAutoLoadPolicy.preferredCandidateId(ready))
    }

    @Test
    fun `falls back to the first ready model when nothing matches a preference`() {
        val ready = listOf("some_other_llm", "another_llm")
        assertEquals("some_other_llm", ModelAutoLoadPolicy.preferredCandidateId(ready))
    }

    @Test
    fun `returns null when nothing is ready`() {
        assertNull(ModelAutoLoadPolicy.preferredCandidateId(emptyList()))
    }
}
