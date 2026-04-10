package com.runanywhere.sdk

import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.public.extensions.STT.STTConfiguration
import com.runanywhere.sdk.public.extensions.STT.STTOptions
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class SarvamSTTTest {

    @Test
    fun `SARVAM enum exists with correct rawValue`() {
        val sarvam = InferenceFramework.SARVAM
        assertEquals("Sarvam", sarvam.rawValue)
    }

    @Test
    fun `SARVAM displayName is correct`() {
        assertEquals("Sarvam AI", InferenceFramework.SARVAM.displayName)
    }

    @Test
    fun `SARVAM analyticsKey is correct`() {
        assertEquals("sarvam", InferenceFramework.SARVAM.analyticsKey)
    }

    @Test
    fun `fromRawValue resolves SARVAM`() {
        assertEquals(InferenceFramework.SARVAM, InferenceFramework.fromRawValue("Sarvam"))
        assertEquals(InferenceFramework.SARVAM, InferenceFramework.fromRawValue("sarvam"))
    }

    @Test
    fun `fromRawValue with unknown string returns UNKNOWN`() {
        assertEquals(InferenceFramework.UNKNOWN, InferenceFramework.fromRawValue("nonexistent"))
    }

    @Test
    fun `STTConfiguration accepts SARVAM framework`() {
        val config = STTConfiguration(
            modelId = "sarvam:saarika:v2.5",
            language = "hi-IN",
            preferredFramework = InferenceFramework.SARVAM,
        )

        assertEquals(InferenceFramework.SARVAM, config.preferredFramework)
        assertEquals("sarvam:saarika:v2.5", config.modelId)
        assertEquals("hi-IN", config.language)
    }

    @Test
    fun `STTConfiguration with SARVAM validates successfully`() {
        val config = STTConfiguration(
            modelId = "sarvam:saarika:v2.5",
            preferredFramework = InferenceFramework.SARVAM,
        )
        config.validate()
    }

    @Test
    fun `STTOptions for Sarvam with Hindi language`() {
        val options = STTOptions(
            language = "hi-IN",
            enablePunctuation = true,
            enableDiarization = false,
            enableTimestamps = true,
        )

        assertEquals("hi-IN", options.language)
        assertTrue(options.enablePunctuation)
        assertTrue(options.enableTimestamps)
    }

    @Test
    fun `STTOptions for Sarvam supports all Indic languages`() {
        val indicLanguages = listOf(
            "en-IN", "hi-IN", "bn-IN", "ta-IN", "te-IN",
            "mr-IN", "kn-IN", "gu-IN", "ml-IN", "pa-IN", "od-IN", "ur-IN",
        )

        indicLanguages.forEach { lang ->
            val options = STTOptions(language = lang)
            assertEquals(lang, options.language)
        }
    }

    @Test
    fun `SARVAM is listed in framework entries`() {
        val frameworks = InferenceFramework.entries
        assertTrue(frameworks.contains(InferenceFramework.SARVAM))
    }

    @Test
    fun `SARVAM is distinct from other frameworks`() {
        val sarvam = InferenceFramework.SARVAM
        assertTrue(sarvam != InferenceFramework.ONNX)
        assertTrue(sarvam != InferenceFramework.LLAMA_CPP)
        assertTrue(sarvam != InferenceFramework.UNKNOWN)
    }
}
