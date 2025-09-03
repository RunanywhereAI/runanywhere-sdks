package com.runanywhere.sdk.components.base

import kotlinx.coroutines.flow.Flow

/**
 * Base component interface for all SDK components
 */
interface Component {
    suspend fun initialize(config: ComponentConfig)
    suspend fun cleanup()
}

/**
 * Configuration base interface
 */
interface ComponentConfig

/**
 * VAD Component interface
 */
interface VADComponent : Component {
    fun processAudioChunk(audio: FloatArray): VADResult
}

/**
 * STT Component interface
 */
interface STTComponent : Component {
    suspend fun transcribe(audioData: ByteArray): TranscriptionResult
    fun transcribeStream(audioFlow: Flow<ByteArray>): Flow<TranscriptionUpdate>
}

/**
 * VAD Result data class
 */
data class VADResult(
    val isSpeech: Boolean,
    val confidence: Float,
    val timestamp: Long = System.currentTimeMillis()
)

/**
 * Transcription result data class
 */
data class TranscriptionResult(
    val text: String,
    val confidence: Float,
    val language: String,
    val duration: Double
)

/**
 * Transcription update for streaming
 */
data class TranscriptionUpdate(
    val text: String,
    val isFinal: Boolean,
    val timestamp: Long = System.currentTimeMillis()
)
