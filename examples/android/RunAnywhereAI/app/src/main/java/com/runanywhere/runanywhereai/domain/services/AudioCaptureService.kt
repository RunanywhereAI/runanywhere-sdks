package com.runanywhere.runanywhereai.domain.services

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import com.runanywhere.sdk.audio.AndroidAudioCapture
import com.runanywhere.sdk.audio.AudioCaptureOptions
import kotlinx.coroutines.flow.Flow
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Service for capturing audio from the device microphone
 * Wrapper around SDK's AndroidAudioCapture for backward compatibility
 *
 * **Note**: This is now a thin wrapper. Consider using AndroidAudioCapture directly from the SDK:
 * ```kotlin
 * import com.runanywhere.sdk.audio.AndroidAudioCapture
 * import com.runanywhere.sdk.audio.AudioCaptureOptions
 *
 * val audioCapture = AndroidAudioCapture(
 *     context = context,
 *     options = AudioCaptureOptions.SPEECH_RECOGNITION
 * )
 * ```
 */
class AudioCaptureService(
    private val context: Context,
    options: AudioCaptureOptions = AudioCaptureOptions.SPEECH_RECOGNITION
) {

    // Delegate to SDK's AndroidAudioCapture
    private val sdkAudioCapture = AndroidAudioCapture(context, options)

    companion object {
        // Constants kept for backward compatibility
        private const val SAMPLE_RATE = 16000 // 16kHz for Whisper compatibility
    }

    /**
     * Check if we have microphone permission
     */
    fun hasRecordPermission(): Boolean {
        return ActivityCompat.checkSelfPermission(
            context,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }

    /**
     * Start capturing audio and emit audio chunks as a Flow
     * Returns PCM audio data at 16kHz, mono, 16-bit
     */
    fun startCapture(): Flow<ByteArray> {
        // Convert VoiceAudioChunk to ByteArray for backward compatibility
        return kotlinx.coroutines.flow.flow {
            sdkAudioCapture.startContinuousCapture().collect { chunk ->
                // Convert float samples back to 16-bit PCM bytes
                val bytes = floatsToBytes(chunk.samples)
                emit(bytes)
            }
        }
    }

    /**
     * Stop audio capture
     */
    fun stopCapture() {
        sdkAudioCapture.stopCapture()
    }

    /**
     * Calculate RMS (Root Mean Square) for audio level visualization
     * Matches iOS implementation for waveform display
     */
    fun calculateRMS(audioData: ByteArray): Float {
        if (audioData.isEmpty()) return 0f

        val shorts = ByteBuffer.wrap(audioData)
            .order(ByteOrder.LITTLE_ENDIAN)
            .asShortBuffer()

        var sum = 0.0
        while (shorts.hasRemaining()) {
            val sample = shorts.get().toFloat() / Short.MAX_VALUE
            sum += sample * sample
        }

        return kotlin.math.sqrt(sum / (audioData.size / 2)).toFloat()
    }

    /**
     * Get the current recording state
     */
    fun isRecording(): Boolean = sdkAudioCapture.isAudioCaptureAvailable()

    /**
     * Clean up resources
     */
    fun release() {
        sdkAudioCapture.stopCapture()
    }

    // MARK: - Private Helper Methods

    /**
     * Convert float samples to 16-bit PCM bytes
     */
    private fun floatsToBytes(samples: FloatArray): ByteArray {
        val bytes = ByteArray(samples.size * 2)
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)

        samples.forEach { sample ->
            val shortValue = (sample * Short.MAX_VALUE).toInt()
                .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
            buffer.putShort(shortValue)
        }

        return bytes
    }
}
