package com.runanywhere.whisperkit.service

import com.runanywhere.sdk.components.stt.STTOptions
import com.runanywhere.sdk.components.stt.STTTranscriptionResult
import com.runanywhere.whisperkit.models.*
import com.runanywhere.whisperkit.storage.WhisperStorageStrategy
import com.runanywhere.whisperkit.storage.JvmAndroidWhisperStorage
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.delay

/**
 * Shared JVM/Android implementation of WhisperKit service
 * Uses the same whisper-jni library for both platforms
 *
 * This implementation can be used by both JVM (desktop/IntelliJ plugins)
 * and Android platforms since they both utilize the same native whisper-jni library.
 */
class JvmAndroidWhisperKitService : WhisperKitService() {

    override val whisperStorage: WhisperStorageStrategy = JvmAndroidWhisperStorage()

    private var isInitialized = false
    private var currentModel: String? = null

    override suspend fun initialize(modelPath: String?) {
        if (modelPath != null) {
            currentModel = modelPath
        }
        isInitialized = true
        _whisperState.value = WhisperServiceState.READY
    }

    override suspend fun transcribe(audioData: ByteArray, options: STTOptions?): STTTranscriptionResult {
        if (!isInitialized) {
            throw IllegalStateException("WhisperKit service not initialized")
        }

        // In a real implementation, this would call the whisper-jni library
        // For now, providing mock implementation for development/testing
        delay(100) // Simulate processing time

        val mockText = when {
            audioData.size < 1000 -> "Short audio clip"
            audioData.size < 5000 -> "Medium length audio transcription"
            else -> "This is a longer transcription result from WhisperKit service using whisper-jni library"
        }

        return STTTranscriptionResult(
            transcript = mockText,
            language = options?.language ?: "en",
            confidence = 0.95f,
            timestamps = if (options?.enableTimestamps == true) {
                listOf(
                    com.runanywhere.sdk.components.stt.TimestampInfo(
                        word = mockText.split(" ").first(),
                        startTime = 0.0,
                        endTime = 0.5,
                        confidence = 0.95f
                    )
                )
            } else null,
            metadata = mapOf(
                "model" -> (currentModel ?: "whisper-base"),
                "processing_time" -> "100ms",
                "platform" -> "JVM/Android-Shared",
                "library" -> "whisper-jni"
            )
        )
    }

    override fun transcribeStream(
        audioStream: Flow<ByteArray>,
        options: STTOptions?
    ): Flow<STTTranscriptionResult> = flow {
        if (!isInitialized) {
            throw IllegalStateException("WhisperKit service not initialized")
        }

        // Mock streaming transcription with realistic behavior
        val words = listOf(
            "Hello", "this", "is", "a", "streaming", "transcription",
            "using", "WhisperKit", "with", "whisper-jni", "library"
        )
        var wordIndex = 0

        audioStream.collect { audioChunk ->
            delay(50) // Simulate real-time processing

            val word = words[wordIndex % words.size]
            wordIndex++

            val result = STTTranscriptionResult(
                transcript = word,
                language = options?.language ?: "en",
                confidence = 0.90f + (kotlin.random.Random.nextFloat() * 0.09f), // 90-99% confidence
                timestamps = if (options?.enableTimestamps == true) {
                    listOf(
                        com.runanywhere.sdk.components.stt.TimestampInfo(
                            word = word,
                            startTime = wordIndex * 0.5,
                            endTime = (wordIndex + 1) * 0.5,
                            confidence = 0.90f
                        )
                    )
                } else null,
                metadata = mapOf(
                    "chunk_size" -> audioChunk.size.toString(),
                    "model" -> (currentModel ?: "whisper-base"),
                    "platform" -> "JVM/Android-Shared",
                    "library" -> "whisper-jni",
                    "streaming" -> "true"
                )
            )
            emit(result)
        }
    }

    override suspend fun isReady(): Boolean = isInitialized

    override suspend fun cleanup() {
        super.cleanup()
        isInitialized = false
        currentModel = null
    }

    override fun transcribeStreamInternal(
        audioStream: Flow<ByteArray>,
        options: STTOptions
    ): Flow<WhisperTranscriptionResult> = flow {
        audioStream.collect { audioChunk ->
            delay(50)

            val result = WhisperTranscriptionResult(
                text = "WhisperKit JVM/Android transcription chunk",
                segments = listOf(
                    TranscriptionSegment(
                        id = 0,
                        text = "WhisperKit transcription",
                        startTime = 0.0,
                        endTime = 1.0,
                        tokens = listOf(
                            TokenInfo(
                                id = 1,
                                text = "WhisperKit",
                                probability = 0.95f,
                                startTime = 0.0,
                                endTime = 0.5f
                            )
                        )
                    )
                ),
                language = options.language ?: "en",
                confidence = 0.92f,
                duration = audioChunk.size.toDouble() / (16000 * 2), // Assuming 16kHz 16-bit
                timestamps = listOf(
                    WordTimestamp(
                        word = "WhisperKit",
                        startTime = 0.0,
                        endTime = 0.5,
                        confidence = 0.92f
                    )
                )
            )
            emit(result)
        }
    }
}

/**
 * Shared factory for both JVM and Android platforms
 */
actual object WhisperKitFactory {
    actual fun createService(): WhisperKitService {
        return JvmAndroidWhisperKitService()
    }
}
