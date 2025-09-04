package com.runanywhere.sdk

import com.runanywhere.sdk.events.TranscriptionEvent
import com.runanywhere.sdk.public.RunAnywhereSTT
import com.runanywhere.sdk.public.STTSDKConfig
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class RunAnywhereSTTTest {

    @Before
    fun setup() = runTest {
        // Clean up any previous state
        if (RunAnywhereSTT.isInitialized()) {
            RunAnywhereSTT.cleanup()
        }
    }

    @After
    fun tearDown() = runTest {
        RunAnywhereSTT.cleanup()
    }

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

    @Test
    fun `test initialization`() = runTest {
        assertFalse(RunAnywhereSTT.isInitialized())

        RunAnywhereSTT.initialize()

        assertTrue(RunAnywhereSTT.isInitialized())
    }

    @Test
    fun `test initialization with custom config`() = runTest {
        val config = STTSDKConfig(
            modelId = "whisper-small",
            enableVAD = false,
            language = "es"
        )

        RunAnywhereSTT.initialize(config)

        assertTrue(RunAnywhereSTT.isInitialized())
    }

    @Test
    fun `test transcribe returns mock result`() = runTest {
        RunAnywhereSTT.initialize()

        val audioData = ByteArray(1000)
        val result = RunAnywhereSTT.transcribe(audioData)

        assertEquals("This is a mock transcription result", result)
    }

    @Test
    fun `test transcribe stream returns expected events`() = runTest {
        RunAnywhereSTT.initialize()

        val audioStream = flowOf(ByteArray(100), ByteArray(200))
        val events = RunAnywhereSTT.transcribeStream(audioStream).toList()

        assertTrue(events.any { it is TranscriptionEvent.SpeechStart })
        assertTrue(events.any { it is TranscriptionEvent.PartialTranscription })
        assertTrue(events.any { it is TranscriptionEvent.FinalTranscription })
        assertTrue(events.any { it is TranscriptionEvent.SpeechEnd })
    }

    @Test(expected = IllegalStateException::class)
    fun `test transcribe without initialization throws exception`() = runTest {
        val audioData = ByteArray(1000)
        RunAnywhereSTT.transcribe(audioData)
    }

    @Test
    fun `test cleanup`() = runTest {
        RunAnywhereSTT.initialize()
        assertTrue(RunAnywhereSTT.isInitialized())

        RunAnywhereSTT.cleanup()
        assertFalse(RunAnywhereSTT.isInitialized())
    }
}
