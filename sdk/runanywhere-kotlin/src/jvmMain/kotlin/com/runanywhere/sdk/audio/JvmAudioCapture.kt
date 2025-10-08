package com.runanywhere.sdk.audio

import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import javax.sound.sampled.*
import kotlin.coroutines.cancellation.CancellationException

/**
 * JVM Audio capture implementation using javax.sound.sampled
 *
 * This implementation mirrors the iOS AudioCapture class exactly,
 * providing 16kHz mono audio capture with 100ms chunk processing.
 */
class JvmAudioCapture {
    private val logger = SDKLogger("JvmAudioCapture")

    // Audio configuration matching iOS (16kHz mono, 16-bit)
    private val sampleRate = 16000f
    private val channels = 1 // Mono
    private val sampleSizeInBits = 16
    private val frameSize = channels * sampleSizeInBits / 8 // 2 bytes per frame

    // Buffer configuration (iOS pattern: 100ms chunks)
    private val minBufferSize = (sampleRate * 0.1f).toInt() * frameSize // 100ms in bytes
    private val bufferSizeFrames = minBufferSize / frameSize

    private var targetDataLine: TargetDataLine? = null
    private var isRecording = false
    private var sequenceNumber = 0

    // Audio format for capture
    private val audioFormat = AudioFormat(
        sampleRate,
        sampleSizeInBits,
        channels,
        true,  // signed
        false  // little-endian
    )

    /**
     * Start continuous audio capture
     * Returns a Flow of VoiceAudioChunk similar to iOS AudioCapture
     */
    fun startContinuousCapture(): Flow<VoiceAudioChunk> = channelFlow {
        try {
            logger.info("Starting continuous audio capture at ${sampleRate}Hz, ${channels} channel(s)")

            // Initialize audio line
            val line = initializeAudioLine()
            targetDataLine = line

            // Start recording
            line.start()
            isRecording = true
            sequenceNumber = 0

            logger.info("Audio capture started successfully")

            // Capture loop (similar to iOS audio processing)
            val buffer = ByteArray(minBufferSize)

            while (isActive && isRecording) {
                try {
                    val bytesRead = line.read(buffer, 0, buffer.size)

                    if (bytesRead > 0) {
                        // Convert to Float samples for processing
                        val samples = convertPCMBytesToFloat(buffer, bytesRead)

                        // Create audio chunk (iOS pattern)
                        val chunk = VoiceAudioChunk(
                            samples = samples,
                            timestamp = System.currentTimeMillis() / 1000.0,
                            sampleRate = sampleRate.toInt(),
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
                    if (e is LineUnavailableException) {
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

        val line = initializeAudioLine()
        val audioData = ByteArrayOutputStream()

        try {
            line.start()
            isRecording = true

            val startTime = System.currentTimeMillis()
            val buffer = ByteArray(minBufferSize)

            while (isRecording && (System.currentTimeMillis() - startTime) < durationMs) {
                val bytesRead = line.read(buffer, 0, buffer.size)
                if (bytesRead > 0) {
                    audioData.write(buffer, 0, bytesRead)
                }
            }

            logger.info("Audio recording completed: ${audioData.size()} bytes")
            return@withContext audioData.toByteArray()

        } finally {
            line.stop()
            line.close()
            isRecording = false
        }
    }

    /**
     * Stop audio capture
     */
    fun stopCapture() {
        logger.info("Stopping audio capture")
        isRecording = false

        targetDataLine?.let { line ->
            try {
                line.stop()
                line.close()
                logger.info("Audio line stopped and closed")
            } catch (e: Exception) {
                logger.error("Error stopping audio line", e)
            }
        }

        targetDataLine = null
        sequenceNumber = 0
    }

    /**
     * Initialize audio input line with proper configuration
     */
    private fun initializeAudioLine(): TargetDataLine {
        logger.debug("Initializing audio input line")

        // Check if audio format is supported
        if (!AudioSystem.isLineSupported(DataLine.Info(TargetDataLine::class.java, audioFormat))) {
            throw AudioCaptureException("Audio format not supported: $audioFormat")
        }

        try {
            // Get available mixer info for debugging
            val mixers = AudioSystem.getMixerInfo()
            logger.debug("Available audio mixers: ${mixers.size}")

            // Get the line
            val line = AudioSystem.getLine(
                DataLine.Info(TargetDataLine::class.java, audioFormat)
            ) as TargetDataLine

            // Open the line with buffer size
            val bufferSize = bufferSizeFrames * 4 // 4x buffer for smooth capture
            line.open(audioFormat, bufferSize)

            logger.info("Audio line opened successfully - Format: $audioFormat, Buffer: $bufferSize frames")

            return line

        } catch (e: LineUnavailableException) {
            logger.error("Audio line unavailable", e)
            throw AudioCaptureException("Audio input line unavailable: ${e.message}", e)
        } catch (e: Exception) {
            logger.error("Failed to initialize audio line", e)
            throw AudioCaptureException("Failed to initialize audio: ${e.message}", e)
        }
    }

    /**
     * Convert PCM bytes to float samples
     * Same conversion logic as in JvmWhisperSTTService for consistency
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
            AudioSystem.isLineSupported(DataLine.Info(TargetDataLine::class.java, audioFormat))
        } catch (e: Exception) {
            logger.error("Error checking audio capture availability", e)
            false
        }
    }

    /**
     * Get available audio input devices
     */
    fun getAvailableInputDevices(): List<String> {
        return try {
            AudioSystem.getMixerInfo()
                .filter { mixerInfo ->
                    val mixer = AudioSystem.getMixer(mixerInfo)
                    mixer.targetLineInfo.any { lineInfo ->
                        lineInfo is DataLine.Info &&
                        TargetDataLine::class.java.isAssignableFrom(lineInfo.lineClass)
                    }
                }
                .map { it.name }
        } catch (e: Exception) {
            logger.error("Error getting audio input devices", e)
            emptyList()
        }
    }
}

