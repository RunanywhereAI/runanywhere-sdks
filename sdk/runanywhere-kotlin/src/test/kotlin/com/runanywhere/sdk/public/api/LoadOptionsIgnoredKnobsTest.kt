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
 * Characterizes which [LoadOptions] fields `models.load()` rejects at
 * preflight because the commons load ABI has no wire path for them yet
 * (PR #605 review issue 8). Per the v4 public API spec, "every accepted
 * field is implemented end to end or fails preflight" — silently dropping
 * them is forbidden, so unsupported knobs throw instead of merely warning.
 * `framework`/`backendPreferences` (single entry) are excluded because they
 * do reach commons.
 */
class LoadOptionsIgnoredKnobsTest {
    @Test
    fun `null options has no unsupported knobs`() {
        assertTrue(null.unsupportedLoadKnobs().isEmpty())
    }

    @Test
    fun `framework alone is not reported as unsupported`() {
        val options = LoadOptions(framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP)
        assertTrue(options.unsupportedLoadKnobs().isEmpty())
    }

    @Test
    fun `a single backendPreferences entry is not reported as unsupported`() {
        val options = LoadOptions(backendPreferences = listOf(BackendPreference(InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP)))
        assertTrue(options.unsupportedLoadKnobs().isEmpty())
    }

    @Test
    fun `contextLength threads and accelerator are each reported`() {
        assertEquals(listOf("contextLength"), LoadOptions(contextLength = 4096).unsupportedLoadKnobs())
        assertEquals(listOf("threads"), LoadOptions(threads = 4).unsupportedLoadKnobs())
        assertEquals(listOf("accelerator"), LoadOptions(accelerator = AcceleratorPolicy.GPU).unsupportedLoadKnobs())
        assertEquals(listOf("accelerator"), LoadOptions(useGpu = true).unsupportedLoadKnobs())
    }

    @Test
    fun `multiple backendPreferences entries are reported`() {
        val options =
            LoadOptions(
                backendPreferences =
                    listOf(
                        BackendPreference(InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP),
                        BackendPreference(InferenceFramework.INFERENCE_FRAMEWORK_ONNX),
                    ),
            )
        assertTrue(options.unsupportedLoadKnobs().single().startsWith("backendPreferences"))
    }

    @Test
    fun `all placement knobs combine in a stable order`() {
        val options = LoadOptions(contextLength = 4096, threads = 4, accelerator = AcceleratorPolicy.CPU)
        assertEquals(listOf("contextLength", "threads", "accelerator"), options.unsupportedLoadKnobs())
    }
}
