package com.runanywhere.runanywhereai.domain.services

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.core.app.ActivityCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.coroutines.coroutineContext

/**
 * Service for capturing audio from the device microphone
 * Matches iOS AudioCaptureService functionality
 */
class AudioCaptureService(private val context: Context) {

    companion object {
        private const val SAMPLE_RATE = 16000 // 16kHz for Whisper compatibility
        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
        private const val BUFFER_SIZE_MULTIPLIER = 2
    }

    private var audioRecord: AudioRecord? = null
    private var isRecording = false

    // Check if we have microphone permission
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
    fun startCapture(): Flow<ByteArray> = flow {
        if (!hasRecordPermission()) {
            throw SecurityException("Microphone permission not granted")
        }

        val minBufferSize = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            CHANNEL_CONFIG,
            AUDIO_FORMAT
        )

        if (minBufferSize == AudioRecord.ERROR || minBufferSize == AudioRecord.ERROR_BAD_VALUE) {
            throw IllegalStateException("Failed to get minimum buffer size")
        }

        val bufferSize = minBufferSize * BUFFER_SIZE_MULTIPLIER

        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            SAMPLE_RATE,
            CHANNEL_CONFIG,
            AUDIO_FORMAT,
            bufferSize
        ).apply {
            if (state != AudioRecord.STATE_INITIALIZED) {
                throw IllegalStateException("Failed to initialize AudioRecord")
            }
        }

        val buffer = ByteArray(bufferSize)

        withContext(Dispatchers.IO) {
            audioRecord?.startRecording()
            isRecording = true

            while (isRecording && coroutineContext.isActive) {
                val bytesRead = audioRecord?.read(buffer, 0, buffer.size) ?: 0

                if (bytesRead > 0) {
                    // Emit a copy of the valid audio data
                    emit(buffer.copyOfRange(0, bytesRead))
                }
            }
        }
    }.flowOn(Dispatchers.IO)

    /**
     * Stop audio capture
     */
    fun stopCapture() {
        isRecording = false
        audioRecord?.apply {
            if (state == AudioRecord.STATE_INITIALIZED) {
                stop()
                release()
            }
        }
        audioRecord = null
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
    fun isRecording(): Boolean = isRecording

    /**
     * Clean up resources
     */
    fun release() {
        stopCapture()
    }
}
