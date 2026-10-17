/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.public.api

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * `LLMGenerationOptions.min_p` is `optional` (idl/llm_options.proto): absent means
 * "use the IDL default" (0.05), while an explicit 0.0 means "min-p sampling off".
 * [LlmOptions.toProto] used to write `minP ?: 0f`, so a caller who set any other
 * knob sent an explicit 0.0 and silently switched min-p sampling off, including on
 * every RAG query once commons started honouring a present `min_p`.
 */
class MinPMappingTest {
    @Test
    fun `an unset minP stays absent on the wire`() {
        assertNull(LlmOptions().toProto().min_p)
    }

    @Test
    fun `setting only another knob leaves minP absent`() {
        assertNull(LlmOptions(temperature = 0.3f).toProto().min_p)
    }

    @Test
    fun `an explicit minP is forwarded`() {
        assertEquals(0.2f, LlmOptions(minP = 0.2f).toProto().min_p)
    }

    @Test
    fun `an explicit zero minP is preserved as zero`() {
        // 0.0 is a legal request for "min-p off"; only an unset value may become absent.
        assertEquals(0f, LlmOptions(minP = 0f).toProto().min_p)
    }

    @Test
    fun `a RAG query that sets only temperature leaves minP absent`() {
        val proto =
            ragQueryProto(
                question = "where is rag",
                config = RagConfig(),
                options = RagQueryOptions(generation = LlmOptions(temperature = 0.3f)),
            )
        assertNull(proto.generation?.min_p)
    }

    @Test
    fun `a RAG query forwards an explicit minP`() {
        val proto =
            ragQueryProto(
                question = "where is rag",
                config = RagConfig(),
                options = RagQueryOptions(generation = LlmOptions(minP = 0.1f)),
            )
        assertEquals(0.1f, proto.generation?.min_p)
    }
}
