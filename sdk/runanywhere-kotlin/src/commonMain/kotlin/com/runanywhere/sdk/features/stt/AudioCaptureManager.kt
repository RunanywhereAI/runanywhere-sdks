package com.runanywhere.sdk.features.stt

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow

/**
 * Audio capture data chunk
 */
data class AudioChunk(
    /** Raw PCM audio data (16-bit, 16kHz, mono) */
    val data: ByteArray,
    /** Timestamp when this chunk was captured (epoch millis) */
    val timestamp: Long,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is AudioChunk) return false
        return data.contentEquals(other.data) && timestamp == other.timestamp
    }

    override fun hashCode(): Int {
        var result = data.contentHashCode()
        result = 31 * result + timestamp.hashCode()
        return result
    }
}

/**
 * Audio capture error types
 */
sealed class AudioCaptureError : Exception() {
    object PermissionDenied : AudioCaptureError() {
        override val message = "Microphone permission denied"
    }

    object FormatConversionFailed : AudioCaptureError() {
        override val message = "Failed to convert audio format"
    }

    object DeviceNotAvailable : AudioCaptureError() {
        override val message = "Audio input device not available"
    }

    data class InitializationFailed(override val message: String) : AudioCaptureError()
    data class RecordingFailed(override val message: String) : AudioCaptureError()
}

/**
 * Manages audio capture from microphone for STT services.
 * Matches iOS AudioCaptureManager exactly.
 *
 * This is a shared utility that works with any STT backend (ONNX, WhisperKit, etc.).
 * It captures audio at 16kHz mono Int16 format, which is the standard input format
 * for speech recognition models like Whisper.
 *
 * Usage:
 * ```kotlin
 * val capture = AudioCaptureManager.create()
 * val granted = capture.requestPermission()
 * if (granted) {
 *     capture.startRecording().collect { audioChunk ->
 *         // Feed audioChunk to your STT service
 *     }
 * }
 * ```
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/STT/Services/AudioCaptureManager.swift
 */
interface AudioCaptureManager {
    /**
     * Whether recording is currently active
     */
    val isRecording: StateFlow<Boolean>

    /**
     * Current audio level (0.0 to 1.0) for visualization
     */
    val audioLevel: StateFlow<Float>

    /**
     * Target sample rate for audio capture (default: 16000 Hz for Whisper)
     */
    val targetSampleRate: Int
        get() = 16000

    /**
     * Request microphone permission
     * @return true if permission was granted, false otherwise
     */
    suspend fun requestPermission(): Boolean

    /**
     * Check if microphone permission has been granted
     */
    suspend fun hasPermission(): Boolean

    /**
     * Start recording audio from microphone
     * @return Flow of audio chunks that can be collected
     * @throws AudioCaptureError if recording fails to start
     */
    suspend fun startRecording(): Flow<AudioChunk>

    /**
     * Stop recording audio
     */
    fun stopRecording()

    /**
     * Clean up resources
     */
    suspend fun cleanup()

    companion object {
        /**
         * Create a platform-specific AudioCaptureManager instance
         */
        fun create(): AudioCaptureManager = createAudioCaptureManager()
    }
}

/**
 * Platform-specific factory for AudioCaptureManager
 */
expect fun createAudioCaptureManager(): AudioCaptureManager
