package com.runanywhere.sdk.features.stt

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
import javax.sound.sampled.AudioFormat
import javax.sound.sampled.AudioSystem
import javax.sound.sampled.DataLine
import javax.sound.sampled.LineUnavailableException
import javax.sound.sampled.TargetDataLine
import kotlin.coroutines.coroutineContext
import kotlin.math.log10
import kotlin.math.sqrt

/**
 * Platform-specific factory for JVM
 */
actual fun createAudioCaptureManager(): AudioCaptureManager = JvmAudioCaptureManager()

/**
 * JVM implementation of AudioCaptureManager using Java Sound API.
 * Captures audio at 16kHz mono 16-bit PCM format.
 *
 * Matches iOS AudioCaptureManager behavior exactly.
 */
class JvmAudioCaptureManager : AudioCaptureManager {
    private val logger = SDKLogger("AudioCapture")

    private var targetLine: TargetDataLine? = null

    private val _isRecording = MutableStateFlow(false)
    override val isRecording: StateFlow<Boolean> = _isRecording.asStateFlow()

    private val _audioLevel = MutableStateFlow(0.0f)
    override val audioLevel: StateFlow<Float> = _audioLevel.asStateFlow()

    override val targetSampleRate: Int = 16000

    // Audio format: 16kHz, 16-bit, mono, signed, little-endian
    private val audioFormat =
        AudioFormat(
            targetSampleRate.toFloat(),
            16, // sample size in bits
            1, // mono
            true, // signed
            false, // little-endian
        )

    // Buffer size for ~100ms of audio at 16kHz (1600 samples * 2 bytes)
    private val bufferSize = 3200

    init {
        logger.info("JvmAudioCaptureManager initialized")
    }

    override suspend fun requestPermission(): Boolean {
        // On JVM/Desktop, there's typically no permission system for microphone
        // We just check if audio input is available
        return hasPermission()
    }

    override suspend fun hasPermission(): Boolean {
        return try {
            val info = DataLine.Info(TargetDataLine::class.java, audioFormat)
            AudioSystem.isLineSupported(info)
        } catch (e: Exception) {
            logger.error("Error checking audio availability: ${e.message}")
            false
        }
    }

    override suspend fun startRecording(): Flow<AudioChunk> =
        flow {
            if (_isRecording.value) {
                logger.warning("Already recording")
                return@flow
            }

            try {
                val info = DataLine.Info(TargetDataLine::class.java, audioFormat)

                if (!AudioSystem.isLineSupported(info)) {
                    throw AudioCaptureError.DeviceNotAvailable
                }

                val line = AudioSystem.getLine(info) as TargetDataLine
                line.open(audioFormat, bufferSize)
                line.start()

                targetLine = line
                _isRecording.value = true

                logger.info("Recording started - sampleRate: $targetSampleRate, bufferSize: $bufferSize")

                // Audio capture loop
                val buffer = ByteArray(bufferSize)

                while (coroutineContext.isActive && _isRecording.value) {
                    val bytesRead = line.read(buffer, 0, buffer.size)

                    if (bytesRead > 0) {
                        // Copy the data to a new array
                        val audioData = buffer.copyOf(bytesRead)

                        // Update audio level for visualization
                        updateAudioLevel(audioData, bytesRead)

                        // Emit audio chunk
                        emit(AudioChunk(audioData, currentTimeMillis()))
                    }
                }
            } catch (e: LineUnavailableException) {
                logger.error("Audio line unavailable: ${e.message}")
                throw AudioCaptureError.DeviceNotAvailable
            } catch (e: AudioCaptureError) {
                throw e
            } catch (e: Exception) {
                logger.error("Recording error: ${e.message}", throwable = e)
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
            targetLine?.stop()
            targetLine?.close()
            targetLine = null
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

    private fun updateAudioLevel(buffer: ByteArray, count: Int) {
        if (count < 2) return

        // Convert bytes to samples and calculate RMS
        var sum = 0.0
        val sampleCount = count / 2

        for (i in 0 until sampleCount) {
            val low = buffer[i * 2].toInt() and 0xFF
            val high = buffer[i * 2 + 1].toInt()
            val sample = ((high shl 8) or low).toShort().toDouble() / 32768.0 // Normalize
            sum += sample * sample
        }

        val rms = sqrt(sum / sampleCount).toFloat()
        val dbLevel = 20 * log10((rms + 0.0001).toDouble()) // Add small value to avoid log(0)

        // Normalize to 0-1 range (-60dB to 0dB)
        val normalizedLevel = ((dbLevel + 60) / 60).coerceIn(0.0, 1.0).toFloat()
        _audioLevel.value = normalizedLevel
    }
}
