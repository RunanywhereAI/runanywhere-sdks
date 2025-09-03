package com.runanywhere.sdk

import com.runanywhere.sdk.public.RunAnywhereSTT
import com.runanywhere.sdk.public.STTSDKConfig
import kotlinx.coroutines.test.runTest
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class RunAnywhereSTTTest {

    @Test
    fun `test SDK initialization state`() {
        // Initially should not be initialized
        assertFalse(RunAnywhereSTT.isInitialized())
    }

    @Test
    fun `test available models list`() {
        val models = RunAnywhereSTT.getAvailableModels()

        // Should have at least the base models
        assertTrue(models.isNotEmpty())
        assertTrue(models.any { it.id == "whisper-base" })
        assertTrue(models.any { it.id == "whisper-tiny" })
    }

    @Test
    fun `test model availability check`() {
        // Models should not be available initially (not downloaded)
        assertFalse(RunAnywhereSTT.isModelAvailable("whisper-base"))
    }

    @Test
    fun `test configuration creation`() {
        val config = STTSDKConfig(
            modelId = "whisper-base",
            enableVAD = true,
            language = "en"
        )

        assertEquals("whisper-base", config.modelId)
        assertTrue(config.enableVAD)
        assertEquals("en", config.language)
    }
}
