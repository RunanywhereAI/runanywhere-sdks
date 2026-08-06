package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.LLMGenerationOptions
import com.runanywhere.sdk.generated.convenience.defaults
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

class CppBridgeLLMGenerationOptionsTest {
    @Test
    fun `explicit zero temperature remains greedy`() {
        val request =
            LLMGenerationOptions(
                max_output_tokens = 128,
                temperature = 0.0f,
                top_p = 1.0f,
            ).toGenerateRequest(prompt = "test")

        val canonical = assertNotNull(request.options)
        assertEquals(0.0f, canonical.temperature)
        assertEquals(128, canonical.max_output_tokens)
    }

    @Test
    fun `absent options use sampled defaults`() {
        val request = (null as LLMGenerationOptions?).toGenerateRequest(prompt = "test")

        val canonical = assertNotNull(request.options)
        val defaults = LLMGenerationOptions.defaults()
        assertEquals(defaults.temperature, canonical.temperature)
        assertEquals(defaults.max_output_tokens, canonical.max_output_tokens)
        assertEquals(defaults.top_p, canonical.top_p)
        assertEquals(defaults.repeat_penalty, canonical.repeat_penalty)
    }

    @Test
    fun `public options conversion also preserves greedy zero`() {
        val request =
            LLMGenerationOptions(
                max_output_tokens = 64,
                temperature = 0.0f,
                top_p = 1.0f,
            ).toRALLMGenerateRequest("test")

        assertEquals(0.0f, assertNotNull(request.options).temperature)
    }
}
