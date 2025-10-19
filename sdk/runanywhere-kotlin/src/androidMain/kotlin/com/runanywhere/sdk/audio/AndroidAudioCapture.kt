package com.runanywhere.sdk.audio

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.core.app.ActivityCompat
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Android Audio capture implementation using Android AudioRecord
 *
 * This implementation mirrors the iOS AudioCapture class exactly,
 * providing 16kHz mono audio capture with 100ms chunk processing.
 */
class AndroidAudioCapture(
    private val context: Context? = null,
    private val options: AudioCaptureOptions = AudioCaptureOptions.DEFAULT
) {
    private val logger = SDKLogger("AndroidAudioCapture")

    // Audio configuration matching iOS (16kHz mono, 16-bit)
    private val sampleRate = options.sampleRate
    private val channels = options.channels // Mono
    private val audioFormat = when (options.audioFormat) {
        AudioEncoding.PCM_16BIT -> AudioFormat.ENCODING_PCM_16BIT
        AudioEncoding.PCM_8BIT -> AudioFormat.ENCODING_PCM_8BIT
        AudioEncoding.PCM_FLOAT -> AudioFormat.ENCODING_PCM_FLOAT
    }
    private val channelConfig = when (channels) {
        1 -> AudioFormat.CHANNEL_IN_MONO
        2 -> AudioFormat.CHANNEL_IN_STEREO
        else -> throw AudioCaptureException("Unsupported channel count: $channels")
    }
    private val frameSize = channels * when (audioFormat) {
        AudioFormat.ENCODING_PCM_8BIT -> 1
        AudioFormat.ENCODING_PCM_16BIT -> 2
        AudioFormat.ENCODING_PCM_FLOAT -> 4
        else -> throw AudioCaptureException("Unsupported audio format: $audioFormat")
    }

    // Buffer configuration (iOS pattern: 100ms chunks)
    private val minBufferSize = (sampleRate * 0.1f).toInt() * frameSize // 100ms in bytes
    private val bufferSizeFrames = minBufferSize / frameSize

    private var audioRecord: AudioRecord? = null
    private var isRecording = false
    private var sequenceNumber = 0

    /**
     * Start continuous audio capture
     * Returns a Flow of VoiceAudioChunk similar to iOS AudioCapture
     */
    fun startContinuousCapture(): Flow<VoiceAudioChunk> = flow {
        if (!hasRecordPermission()) {
            throw AudioCaptureException("Microphone permission not granted")
        }

        val audioSource = mapAudioSource(options.audioSource)

        val minBufSize = AudioRecord.getMinBufferSize(
            sampleRate,
            channelConfig,
            audioFormat
        )

        if (minBufSize == AudioRecord.ERROR || minBufSize == AudioRecord.ERROR_BAD_VALUE) {
            throw AudioCaptureException("Invalid audio configuration for Android AudioRecord")
        }

        val bufferSize = minBufSize * options.bufferSizeMultiplier

        audioRecord = AudioRecord(
            audioSource,
            sampleRate,
            channelConfig,
            audioFormat,
            bufferSize
        ).apply {
            if (state != AudioRecord.STATE_INITIALIZED) {
                throw AudioCaptureException("Failed to initialize AudioRecord")
            }
        }

        val buffer = ByteArray(bufferSize)

        withContext(Dispatchers.IO) {
            audioRecord?.startRecording()
            isRecording = true
            logger.info("Started audio capture: $sampleRate Hz, $channels ch, buffer=$bufferSize bytes")

            while (isRecording && coroutineContext.isActive) {
                val bytesRead = audioRecord?.read(buffer, 0, buffer.size) ?: 0

                if (bytesRead > 0) {
                    // Convert to Float samples for processing
                    val samples = bytesToFloats(buffer, bytesRead)

                    // Create audio chunk (iOS pattern)
                    val chunk = VoiceAudioChunk(
                        samples = samples,
                        timestamp = System.currentTimeMillis() / 1000.0,
                        sampleRate = sampleRate,
                        channels = channels,
                        sequenceNumber = sequenceNumber++,
                        isFinal = false
                    )

                    // Send chunk to flow
                    emit(chunk)
                } else if (bytesRead < 0) {
                    // Handle error codes
                    logger.warn("AudioRecord read error: $bytesRead")
                }
            }
        }
    }.flowOn(Dispatchers.IO)

    /**
     * Record audio for a specific duration and return as ByteArray
     * This method is useful for batch transcription
     */
    suspend fun recordAudio(durationMs: Long): ByteArray = withContext(Dispatchers.IO) {
        logger.info("Recording audio for $durationMs ms")

        val record = initializeAudioRecord()
        val audioData = ByteArrayOutputStream()

        try {
            record.startRecording()
            isRecording = true

            val startTime = System.currentTimeMillis()
            val buffer = ByteArray(minBufferSize)

            while (isRecording && (System.currentTimeMillis() - startTime) < durationMs) {
                val bytesRead = record.read(buffer, 0, buffer.size)
                if (bytesRead > 0) {
                    audioData.write(buffer, 0, bytesRead)
                }
            }

            logger.info("Audio recording completed: ${audioData.size()} bytes")
            return@withContext audioData.toByteArray()

        } finally {
            record.stop()
            record.release()
            isRecording = false
        }
    }

    /**
     * Stop audio capture
     */
    fun stopCapture() {
        logger.info("Stopping audio capture")
        isRecording = false

        audioRecord?.let { record ->
            try {
                record.stop()
                record.release()
                logger.info("Audio record stopped and released")
            } catch (e: Exception) {
                logger.error("Error stopping audio record", e)
            }
        }

        audioRecord = null
        sequenceNumber = 0
    }

    /**
     * Initialize AudioRecord with proper configuration
     */
    private fun initializeAudioRecord(): AudioRecord {
        logger.debug("Initializing Android AudioRecord")

        // Calculate minimum buffer size
        val minBufSize = AudioRecord.getMinBufferSize(
            sampleRate,
            channelConfig,
            audioFormat
        )

        if (minBufSize == AudioRecord.ERROR || minBufSize == AudioRecord.ERROR_BAD_VALUE) {
            throw AudioCaptureException("Invalid audio configuration for Android AudioRecord")
        }

        try {
            // Use 4x minimum buffer for smooth capture
            val bufferSize = minBufSize * options.bufferSizeMultiplier

            val record = AudioRecord(
                mapAudioSource(options.audioSource),
                sampleRate,
                channelConfig,
                audioFormat,
                bufferSize
            )

            if (record.state != AudioRecord.STATE_INITIALIZED) {
                throw AudioCaptureException("Failed to initialize AudioRecord - state: ${record.state}")
            }

            logger.info("AudioRecord initialized successfully - SampleRate: $sampleRate, Buffer: $bufferSize bytes")

            return record

        } catch (e: SecurityException) {
            logger.error("Audio permission denied", e)
            throw AudioCaptureException("Audio recording permission required", e)
        } catch (e: Exception) {
            logger.error("Failed to initialize AudioRecord", e)
            throw AudioCaptureException("Failed to initialize audio: ${e.message}", e)
        }
    }

    /**
     * Convert PCM bytes to float samples
     * Same conversion logic as in JvmAudioCapture for consistency
     */
    private fun bytesToFloats(pcmBytes: ByteArray, bytesRead: Int): FloatArray {
        return when (audioFormat) {
            AudioFormat.ENCODING_PCM_16BIT -> {
                val shorts = ShortArray(bytesRead / 2)
                ByteBuffer.wrap(pcmBytes).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(shorts)
                FloatArray(shorts.size) { i ->
                    shorts[i].toFloat() / Short.MAX_VALUE.toFloat()
                }
            }
            AudioFormat.ENCODING_PCM_FLOAT -> {
                val floats = FloatArray(bytesRead / 4)
                ByteBuffer.wrap(pcmBytes).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer().get(floats)
                floats
            }

            AudioFormat.ENCODING_PCM_8BIT -> {
                FloatArray(bytesRead) { i ->
                    pcmBytes[i].toFloat() / Byte.MAX_VALUE.toFloat()
                }
            }

            else -> throw AudioCaptureException("Unsupported audio format: $audioFormat")
        }
    }

    /**
     * Check if audio capture is available
     */
    fun isAudioCaptureAvailable(): Boolean {
        return try {
            // Check if microphone is available
            val hasMicrophone = context?.packageManager?.hasSystemFeature(
                PackageManager.FEATURE_MICROPHONE
            ) ?: true

            if (!hasMicrophone) {
                logger.warn("Device does not have microphone feature")
                return false
            }

            // Test if we can create AudioRecord
            val testRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                channelConfig,
                audioFormat,
                AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
            )

            val isAvailable = testRecord.state == AudioRecord.STATE_INITIALIZED
            testRecord.release()

            isAvailable
        } catch (e: Exception) {
            logger.error("Error checking audio capture availability", e)
            false
        }
    }

    /**
     * Get available audio input devices (simplified for Android)
     */
    fun getAvailableInputDevices(): List<String> {
        return try {
            val devices = mutableListOf<String>()

            // Basic Android audio sources
            devices.add("Default Microphone")

            // Check if device has specific features
            context?.packageManager?.let { pm ->
                if (pm.hasSystemFeature(PackageManager.FEATURE_MICROPHONE)) {
                    devices.add("Built-in Microphone")
                }
            }

            devices
        } catch (e: Exception) {
            logger.error("Error getting audio input devices", e)
            listOf("Default Microphone")
        }
    }

    /**
     * Check if we have microphone permission
     */
    fun hasRecordPermission(): Boolean {
        return ActivityCompat.checkSelfPermission(
            context!!,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }

    /**
     * Map SDK AudioSource to Android MediaRecorder audio source
     */
    private fun mapAudioSource(source: AudioSource): Int {
        return when (source) {
            AudioSource.DEFAULT -> MediaRecorder.AudioSource.DEFAULT
            AudioSource.MIC -> MediaRecorder.AudioSource.MIC
            AudioSource.VOICE_RECOGNITION -> MediaRecorder.AudioSource.VOICE_RECOGNITION
            AudioSource.VOICE_COMMUNICATION -> MediaRecorder.AudioSource.VOICE_COMMUNICATION
            AudioSource.CAMCORDER -> MediaRecorder.AudioSource.CAMCORDER
            AudioSource.UNPROCESSED -> {
                // UNPROCESSED requires API 24+
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
                    MediaRecorder.AudioSource.UNPROCESSED
                } else {
                    logger.warn("UNPROCESSED audio source not available, using DEFAULT")
                    MediaRecorder.AudioSource.DEFAULT
                }
            }
        }
    }
}
