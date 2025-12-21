package com.runanywhere.sdk.features.stt

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.core.content.ContextCompat
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.currentTimeMillis
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.isActive
import kotlin.coroutines.coroutineContext
import kotlin.math.sqrt

/**
 * Platform-specific factory for Android
 */
actual fun createAudioCaptureManager(): AudioCaptureManager = AndroidAudioCaptureManager()

/**
 * Android implementation of AudioCaptureManager using AudioRecord.
 * Captures audio at 16kHz mono 16-bit PCM format.
 *
 * Matches iOS AudioCaptureManager behavior exactly.
 */
class AndroidAudioCaptureManager : AudioCaptureManager {
    private val logger = SDKLogger("AudioCapture")

    private var audioRecord: AudioRecord? = null

    private val _isRecording = MutableStateFlow(false)
    override val isRecording: StateFlow<Boolean> = _isRecording.asStateFlow()

    private val _audioLevel = MutableStateFlow(0.0f)
    override val audioLevel: StateFlow<Float> = _audioLevel.asStateFlow()

    override val targetSampleRate: Int = 16000

    // Buffer size for ~100ms of audio at 16kHz (1600 samples * 2 bytes)
    private val bufferSize: Int by lazy {
        val minBufferSize = AudioRecord.getMinBufferSize(
            targetSampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        maxOf(minBufferSize, 3200) // At least 100ms of audio
    }

    init {
        logger.info("AndroidAudioCaptureManager initialized")
    }

    override suspend fun requestPermission(): Boolean {
        // On Android, permission must be requested through the Activity
        // This method checks if permission is already granted
        // Actual permission request must be done via Activity.requestPermissions()
        logger.info("Checking microphone permission (request must be done via Activity)")
        return hasPermission()
    }

    override suspend fun hasPermission(): Boolean {
        return try {
            val context = getApplicationContext()
            if (context != null) {
                ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.RECORD_AUDIO,
                ) == PackageManager.PERMISSION_GRANTED
            } else {
                logger.warning("Cannot check permission - no application context")
                false
            }
        } catch (e: Exception) {
            logger.error("Error checking permission: ${e.message}")
            false
        }
    }

    override suspend fun startRecording(): Flow<AudioChunk> = flow {
        if (_isRecording.value) {
            logger.warning("Already recording")
            return@flow
        }

        if (!hasPermission()) {
            throw AudioCaptureError.PermissionDenied
        }

        try {
            // Create AudioRecord
            val record = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                targetSampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize,
            )

            if (record.state != AudioRecord.STATE_INITIALIZED) {
                record.release()
                throw AudioCaptureError.InitializationFailed("AudioRecord failed to initialize")
            }

            audioRecord = record
            record.startRecording()
            _isRecording.value = true

            logger.info("Recording started - sampleRate: $targetSampleRate, bufferSize: $bufferSize")

            // Audio capture loop
            val buffer = ShortArray(bufferSize / 2) // 16-bit samples

            while (coroutineContext.isActive && _isRecording.value) {
                val readCount = record.read(buffer, 0, buffer.size)

                if (readCount > 0) {
                    // Convert shorts to bytes
                    val byteData = ByteArray(readCount * 2)
                    for (i in 0 until readCount) {
                        val sample = buffer[i].toInt()
                        byteData[i * 2] = (sample and 0xFF).toByte()
                        byteData[i * 2 + 1] = ((sample shr 8) and 0xFF).toByte()
                    }

                    // Update audio level for visualization
                    updateAudioLevel(buffer, readCount)

                    // Emit audio chunk
                    emit(AudioChunk(byteData, currentTimeMillis()))
                } else if (readCount < 0) {
                    logger.error("AudioRecord.read error: $readCount")
                    break
                }
            }
        } catch (e: SecurityException) {
            logger.error("Security exception: ${e.message}")
            throw AudioCaptureError.PermissionDenied
        } catch (e: AudioCaptureError) {
            throw e
        } catch (e: Exception) {
            logger.error("Recording error: ${e.message}", e)
            throw AudioCaptureError.RecordingFailed(e.message ?: "Unknown error")
        } finally {
            stopRecordingInternal()
        }
    }.flowOn(Dispatchers.IO)

    override fun stopRecording() {
        if (!_isRecording.value) return
        stopRecordingInternal()
    }

    private fun stopRecordingInternal() {
        try {
            audioRecord?.stop()
            audioRecord?.release()
            audioRecord = null
        } catch (e: Exception) {
            logger.error("Error stopping recording: ${e.message}")
        }

        _isRecording.value = false
        _audioLevel.value = 0.0f
        logger.info("Recording stopped")
    }

    override suspend fun cleanup() {
        stopRecording()
    }

    private fun updateAudioLevel(buffer: ShortArray, count: Int) {
        if (count <= 0) return

        // Calculate RMS (root mean square) for audio level
        var sum = 0.0
        for (i in 0 until count) {
            val sample = buffer[i].toDouble() / 32768.0 // Normalize to -1.0 to 1.0
            sum += sample * sample
        }

        val rms = sqrt(sum / count).toFloat()
        val dbLevel = 20 * kotlin.math.log10((rms + 0.0001).toDouble()) // Add small value to avoid log(0)

        // Normalize to 0-1 range (-60dB to 0dB)
        val normalizedLevel = ((dbLevel + 60) / 60).coerceIn(0.0, 1.0).toFloat()
        _audioLevel.value = normalizedLevel
    }

    private fun getApplicationContext(): Context? {
        // Try to get context through reflection (common pattern in KMP)
        return try {
            val activityThread = Class.forName("android.app.ActivityThread")
            val currentApplication = activityThread.getMethod("currentApplication")
            currentApplication.invoke(null) as? Context
        } catch (e: Exception) {
            null
        }
    }
}
