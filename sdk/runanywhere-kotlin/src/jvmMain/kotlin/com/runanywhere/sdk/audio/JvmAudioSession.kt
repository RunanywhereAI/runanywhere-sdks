package com.runanywhere.sdk.audio

import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.sound.sampled.*
import kotlin.math.max

/**
 * JVM-specific audio session implementation
 * Platform-specific implementation for Java Sound API
 */
class JvmAudioSession {

    private val logger = SDKLogger("JvmAudioSession")
    private var targetDataLine: TargetDataLine? = null
    private var audioFormat: AudioFormat? = null

    private val _isRecording = MutableStateFlow(false)
    val isRecording: StateFlow<Boolean> = _isRecording.asStateFlow()

    private val _isConfigured = MutableStateFlow(false)
    val isConfigured: StateFlow<Boolean> = _isConfigured.asStateFlow()

    private var selectedMixer: Mixer.Info? = null

    /**
     * Configure audio session for recording
     */
    fun configureForRecording(
        sampleRate: Float = 16000f,
        sampleSizeInBits: Int = 16,
        channels: Int = 1,
        signed: Boolean = true,
        bigEndian: Boolean = false
    ): Boolean {
        try {
            audioFormat = AudioFormat(
                sampleRate,
                sampleSizeInBits,
                channels,
                signed,
                bigEndian
            )

            val dataLineInfo = DataLine.Info(
                TargetDataLine::class.java,
                audioFormat
            )

            // Try to get the target data line from selected mixer or default
            targetDataLine = if (selectedMixer != null) {
                val mixer = AudioSystem.getMixer(selectedMixer)
                mixer.getLine(dataLineInfo) as TargetDataLine
            } else {
                AudioSystem.getLine(dataLineInfo) as TargetDataLine
            }

            // Calculate buffer size (0.5 seconds of audio)
            val bufferSize = (sampleRate * channels * (sampleSizeInBits / 8) * 0.5).toInt()
            targetDataLine?.open(audioFormat, max(bufferSize, 4096))

            _isConfigured.value = true
            return true

        } catch (e: LineUnavailableException) {
            logger.error("Audio line unavailable for recording", e)
            return false
        } catch (e: Exception) {
            logger.error("Failed to configure audio recording", e)
            return false
        }
    }

    /**
     * Start audio recording
     */
    fun startRecording(): Boolean {
        if (!_isConfigured.value || _isRecording.value) {
            return false
        }

        return try {
            targetDataLine?.start()
            _isRecording.value = true
            true
        } catch (e: Exception) {
            logger.error("Failed to start audio recording", e)
            false
        }
    }

    /**
     * Stop audio recording
     */
    fun stopRecording(): Boolean {
        if (!_isRecording.value) {
            return false
        }

        return try {
            targetDataLine?.stop()
            _isRecording.value = false
            true
        } catch (e: Exception) {
            logger.error("Failed to stop audio recording", e)
            false
        }
    }

    /**
     * Read audio data from the recording buffer
     */
    fun readAudioData(buffer: ByteArray, offset: Int = 0, length: Int = buffer.size): Int {
        return targetDataLine?.read(buffer, offset, length) ?: -1
    }

    /**
     * Read audio data as shorts (16-bit samples)
     */
    fun readAudioDataAsShorts(buffer: ShortArray): Int {
        val byteBuffer = ByteArray(buffer.size * 2)
        val bytesRead = readAudioData(byteBuffer)

        if (bytesRead <= 0) return bytesRead

        // Convert bytes to shorts
        val shortsRead = bytesRead / 2
        for (i in 0 until shortsRead) {
            val low = byteBuffer[i * 2].toInt() and 0xFF
            val high = byteBuffer[i * 2 + 1].toInt() shl 8
            buffer[i] = (high or low).toShort()
        }

        return shortsRead
    }

    /**
     * Release audio resources
     */
    fun release() {
        try {
            if (_isRecording.value) {
                stopRecording()
            }

            targetDataLine?.close()
            targetDataLine = null
            _isConfigured.value = false

        } catch (e: Exception) {
            logger.error("Failed to release audio resources", e)
        }
    }

    /**
     * Get available audio input devices
     */
    fun getAvailableInputDevices(): List<AudioDevice> {
        val devices = mutableListOf<AudioDevice>()

        val mixerInfos = AudioSystem.getMixerInfo()
        for (info in mixerInfos) {
            val mixer = AudioSystem.getMixer(info)
            val targetLineInfo = mixer.targetLineInfo

            if (targetLineInfo.isNotEmpty()) {
                devices.add(
                    AudioDevice(
                        name = info.name,
                        description = info.description,
                        vendor = info.vendor,
                        version = info.version,
                        mixerInfo = info
                    )
                )
            }
        }

        return devices
    }

    /**
     * Select audio input device
     */
    fun selectInputDevice(device: AudioDevice): Boolean {
        return try {
            selectedMixer = device.mixerInfo
            true
        } catch (e: Exception) {
            logger.error("Failed to select input device: ${device.name}", e)
            false
        }
    }

    /**
     * Get current audio format
     */
    fun getAudioFormat(): AudioFormat? = audioFormat

    /**
     * Check if microphone is available
     */
    fun isMicrophoneAvailable(): Boolean {
        return try {
            val format = AudioFormat(16000f, 16, 1, true, false)
            val info = DataLine.Info(TargetDataLine::class.java, format)
            AudioSystem.isLineSupported(info)
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Get buffer size
     */
    fun getBufferSize(): Int {
        return targetDataLine?.bufferSize ?: 0
    }

    /**
     * Get available bytes in buffer
     */
    fun available(): Int {
        return targetDataLine?.available() ?: 0
    }

    /**
     * Flush the audio buffer
     */
    fun flush() {
        targetDataLine?.flush()
    }
}

/**
 * Audio device information
 */
data class AudioDevice(
    val name: String,
    val description: String,
    val vendor: String,
    val version: String,
    internal val mixerInfo: Mixer.Info
)
