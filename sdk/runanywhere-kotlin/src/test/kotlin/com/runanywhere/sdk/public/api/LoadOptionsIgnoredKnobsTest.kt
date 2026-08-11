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
 * preflight. Commons owns `contextLength`, `accelerator`/`useGpu`, and
 * ordered `backendPreferences` via [ai.runanywhere.proto.v1.ModelLoadRequest];
 * only `threads` (retired from the load ABI, reserved tag 7) still fails
 * preflight rather than being silently dropped.
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
    fun `commons-owned knobs are not reported and only threads is`() {
        assertTrue(LoadOptions(contextLength = 4096).unsupportedLoadKnobs().isEmpty())
        assertEquals(listOf("threads"), LoadOptions(threads = 4).unsupportedLoadKnobs())
        assertTrue(LoadOptions(accelerator = AcceleratorPolicy.GPU).unsupportedLoadKnobs().isEmpty())
        assertTrue(LoadOptions(useGpu = true).unsupportedLoadKnobs().isEmpty())
    }

    @Test
    fun `multiple backendPreferences entries are not reported as unsupported`() {
        val options =
            LoadOptions(
                backendPreferences =
                    listOf(
                        BackendPreference(InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP),
                        BackendPreference(InferenceFramework.INFERENCE_FRAMEWORK_ONNX),
                    ),
            )
        assertTrue(options.unsupportedLoadKnobs().isEmpty())
    }

    @Test
    fun `combined knobs only report retired threads`() {
        val options = LoadOptions(contextLength = 4096, threads = 4, accelerator = AcceleratorPolicy.CPU)
        assertEquals(listOf("threads"), options.unsupportedLoadKnobs())
    }
}
