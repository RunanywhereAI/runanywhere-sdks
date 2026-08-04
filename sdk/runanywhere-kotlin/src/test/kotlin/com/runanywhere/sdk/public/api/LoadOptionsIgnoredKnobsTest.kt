/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.InferenceFramework
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Characterizes which [LoadOptions] fields `models.load()` warns about
 * because the commons load ABI has no wire path for them yet (PR #605
 * review issue 8). `framework` is excluded because it does reach commons.
 */
class LoadOptionsIgnoredKnobsTest {
    @Test
    fun `null options has no ignored knobs`() {
        assertTrue(null.ignoredKnobs().isEmpty())
    }

    @Test
    fun `framework alone is not reported as ignored`() {
        val options = LoadOptions(framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP)
        assertTrue(options.ignoredKnobs().isEmpty())
    }

    @Test
    fun `contextLength threads and useGpu are each reported`() {
        assertEquals(listOf("contextLength"), LoadOptions(contextLength = 4096).ignoredKnobs())
        assertEquals(listOf("threads"), LoadOptions(threads = 4).ignoredKnobs())
        assertEquals(listOf("useGpu"), LoadOptions(useGpu = true).ignoredKnobs())
    }

    @Test
    fun `all placement knobs combine in a stable order`() {
        val options = LoadOptions(contextLength = 4096, threads = 4, useGpu = false)
        assertEquals(listOf("contextLength", "threads", "useGpu"), options.ignoredKnobs())
    }
}
