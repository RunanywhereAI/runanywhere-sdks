package com.runanywhere.sdk.audio

import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import kotlin.coroutines.cancellation.CancellationException

/**
 * Android Audio capture implementation using Android AudioRecord
 *
 * This implementation mirrors the iOS AudioCapture class exactly,
 * providing 16kHz mono audio capture with 100ms chunk processing.
 */
class AndroidAudioCapture(private val context: Context? = null) {
    private val logger = SDKLogger("AndroidAudioCapture")

    // Audio configuration matching iOS (16kHz mono, 16-bit)
    private val sampleRate = 16000
    private val channels = 1 // Mono
    private val audioFormat = AudioFormat.ENCODING_PCM_16BIT
    private val channelConfig = AudioFormat.CHANNEL_IN_MONO
    private val frameSize = channels * 16 / 8 // 2 bytes per frame

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
    fun startContinuousCapture(): Flow<VoiceAudioChunk> = channelFlow {
        try {
            logger.info("Starting continuous audio capture at ${sampleRate}Hz, ${channels} channel(s)")

            // Initialize audio record
            val record = initializeAudioRecord()
            audioRecord = record

            // Start recording
            record.startRecording()
            isRecording = true
            sequenceNumber = 0

            logger.info("Audio capture started successfully")

            // Capture loop (similar to iOS audio processing)
            val buffer = ByteArray(minBufferSize)

            while (isActive && isRecording) {
                try {
                    val bytesRead = record.read(buffer, 0, buffer.size)

                    if (bytesRead > 0) {
                        // Convert to Float samples for processing
                        val samples = convertPCMBytesToFloat(buffer, bytesRead)

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
                        send(chunk)
                    }

                } catch (e: CancellationException) {
                    logger.info("Audio capture cancelled")
                    break
                } catch (e: Exception) {
                    logger.error("Error during audio capture", e)
                    // Continue capturing unless it's a critical error
                    if (e is IllegalStateException) {
                        break
                    }
                }
            }

        } catch (e: Exception) {
            logger.error("Failed to start audio capture", e)
            throw e
        } finally {
            stopCapture()
        }
    }

    /**
     * Record audio for a specific duration and return as ByteArray
     * This method is useful for batch transcription
     */
    suspend fun recordAudio(durationMs: Long): ByteArray = withContext(Dispatchers.IO) {
        logger.info("Recording audio for ${durationMs}ms")

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
            val bufferSize = minBufSize * 4

            val record = AudioRecord(
                MediaRecorder.AudioSource.MIC,
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
    private fun convertPCMBytesToFloat(pcmBytes: ByteArray, bytesRead: Int): FloatArray {
        val sampleCount = bytesRead / 2 // 16-bit samples = 2 bytes each
        val floatArray = FloatArray(sampleCount)

        for (i in 0 until sampleCount) {
            val byteIndex = i * 2

            if (byteIndex + 1 < bytesRead) {
                // Convert little-endian 16-bit signed integer to float [-1.0, 1.0]
                val low = pcmBytes[byteIndex].toInt() and 0xFF
                val high = pcmBytes[byteIndex + 1].toInt()
                val sample = ((high shl 8) or low).toShort()

                // Normalize to [-1.0, 1.0] range
                floatArray[i] = sample / 32768.0f
            } else {
                floatArray[i] = 0.0f
            }
        }

        return floatArray
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
}
