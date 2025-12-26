package com.runanywhere.sdk

import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.runBlocking
import kotlin.test.Test

class SDKTest {
    @Test
    fun testSDKInitialization() =
        runBlocking {
            // Initialize SDK in development mode (no API key needed)
            RunAnywhere.initialize(
                apiKey = "test-api-key",
                environment = SDKEnvironment.DEVELOPMENT,
            )

            // Check if SDK is initialized
            val isInitialized = RunAnywhere.isInitialized
            println("SDK initialized: $isInitialized")

            // Get available models
            val models = RunAnywhere.availableModels()
            println("Available models: ${models.size}")
            models.forEach { model ->
                println("- ${model.name} (${model.id}): ${model.category}")
            }

            // Clean up
            RunAnywhere.cleanup()
        }

    @Test
    fun testSimpleTranscription() =
        runBlocking {
            // Initialize SDK
            RunAnywhere.initialize(
                apiKey = "test-api-key",
                environment = SDKEnvironment.DEVELOPMENT,
            )

            // Create dummy audio data (16-bit PCM at 16kHz, 1 second of silence)
            val audioData = ByteArray(16000 * 2) // 1 second at 16kHz, 16-bit

            try {
                // Try to transcribe
                val result = RunAnywhere.transcribe(audioData)
                println("Transcription result: $result")
            } catch (e: Exception) {
                println("Transcription failed (expected in test environment): ${e.message}")
            }

            // Clean up
            RunAnywhere.cleanup()
        }
}
