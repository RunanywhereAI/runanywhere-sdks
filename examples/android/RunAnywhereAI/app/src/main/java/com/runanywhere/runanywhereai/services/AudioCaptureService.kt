package com.runanywhere.runanywhereai.services

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import androidx.core.app.ActivityCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.sqrt

/**
 * Service for capturing audio from the device microphone.
 *
 * Captures PCM audio at 16kHz, mono, 16-bit for STT model consumption.
 */
class AudioCaptureService(private val context: Context) {

    companion object {
        private const val TAG = "AudioCaptureService"
        const val SAMPLE_RATE = 16000
        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
        private const val CHUNK_SIZE_MS = 100
    }

    private var audioRecord: AudioRecord? = null

    private val _isRecording = MutableStateFlow(false)
    val isRecordingState: StateFlow<Boolean> = _isRecording.asStateFlow()

    fun hasRecordPermission(): Boolean =
        ActivityCompat.checkSelfPermission(
            context, Manifest.permission.RECORD_AUDIO,
        ) == PackageManager.PERMISSION_GRANTED

    /**
     * Start capturing audio and emit audio chunks as a Flow.
     * Returns PCM audio data at 16kHz, mono, 16-bit.
     */
    fun startCapture(): Flow<ByteArray> = callbackFlow {
        if (!hasRecordPermission()) {
            close(SecurityException("RECORD_AUDIO permission not granted"))
            return@callbackFlow
        }

        val bufferSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
        val chunkSize = (SAMPLE_RATE * 2 * CHUNK_SIZE_MS) / 1000

        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE,
                CHANNEL_CONFIG,
                AUDIO_FORMAT,
                bufferSize.coerceAtLeast(chunkSize * 2),
            )

            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                close(IllegalStateException("AudioRecord initialization failed"))
                return@callbackFlow
            }

            audioRecord?.startRecording()
            _isRecording.value = true
            Log.i(TAG, "Audio capture started (${SAMPLE_RATE}Hz)")

            val readJob = launch(Dispatchers.IO) {
                val buffer = ByteArray(chunkSize)
                while (isActive && _isRecording.value) {
                    val bytesRead = audioRecord?.read(buffer, 0, chunkSize) ?: -1
                    if (bytesRead > 0) {
                        trySend(buffer.copyOf(bytesRead))
                    } else if (bytesRead < 0) {
                        Log.w(TAG, "AudioRecord read error: $bytesRead")
                        break
                    }
                }
            }

            awaitClose {
                readJob.cancel()
                stopCaptureInternal()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in audio capture: ${e.message}")
            stopCaptureInternal()
            close(e)
        }
    }

    fun stopCapture() {
        _isRecording.value = false
        stopCaptureInternal()
    }

    private fun stopCaptureInternal() {
        try {
            audioRecord?.stop()
            audioRecord?.release()
            audioRecord = null
            _isRecording.value = false
        } catch (e: Exception) {
            Log.w(TAG, "Error stopping audio capture: ${e.message}")
        }
    }

    /** Calculate RMS for audio level visualization. */
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
        return sqrt(sum / (audioData.size / 2)).toFloat()
    }

    fun release() {
        stopCapture()
    }
}
