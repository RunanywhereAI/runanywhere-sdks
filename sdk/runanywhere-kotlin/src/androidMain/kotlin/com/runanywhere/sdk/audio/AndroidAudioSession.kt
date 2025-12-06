package com.runanywhere.sdk.audio

import android.content.Context
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Android-specific audio session implementation
 * Platform-specific implementation for Android AudioManager
 */
class AndroidAudioSession(private val context: Context) {

    private val logger = SDKLogger("AndroidAudioSession")
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var audioRecord: AudioRecord? = null

    private val _isRecording = MutableStateFlow(false)
    val isRecording: StateFlow<Boolean> = _isRecording.asStateFlow()

    private val _isConfigured = MutableStateFlow(false)
    val isConfigured: StateFlow<Boolean> = _isConfigured.asStateFlow()

    /**
     * Configure audio session for recording
     */
    fun configureForRecording(
        sampleRate: Int = 16000,
        channelConfig: Int = AudioFormat.CHANNEL_IN_MONO,
        audioFormat: Int = AudioFormat.ENCODING_PCM_16BIT
    ): Boolean {
        try {
            // Request audio focus
            val focusRequest = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                android.media.AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                    .build()
            } else {
                null
            }

            val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && focusRequest != null) {
                audioManager.requestAudioFocus(focusRequest)
            } else {
                @Suppress("DEPRECATION")
                audioManager.requestAudioFocus(
                    null,
                    AudioManager.STREAM_MUSIC,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
                )
            }

            if (result != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                return false
            }

            // Calculate buffer size
            val bufferSize = AudioRecord.getMinBufferSize(
                sampleRate,
                channelConfig,
                audioFormat
            )

            if (bufferSize == AudioRecord.ERROR || bufferSize == AudioRecord.ERROR_BAD_VALUE) {
                return false
            }

            // Create AudioRecord instance
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                channelConfig,
                audioFormat,
                bufferSize * 2 // Use 2x minimum buffer for safety
            )

            _isConfigured.value = audioRecord?.state == AudioRecord.STATE_INITIALIZED
            return _isConfigured.value

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
            audioRecord?.startRecording()
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
            audioRecord?.stop()
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
    fun readAudioData(buffer: ShortArray, offset: Int = 0, size: Int = buffer.size): Int {
        return audioRecord?.read(buffer, offset, size) ?: 0
    }

    /**
     * Read audio data as bytes
     */
    fun readAudioData(buffer: ByteArray, offset: Int = 0, size: Int = buffer.size): Int {
        return audioRecord?.read(buffer, offset, size) ?: 0
    }

    /**
     * Release audio resources
     */
    fun release() {
        try {
            if (_isRecording.value) {
                stopRecording()
            }

            audioRecord?.release()
            audioRecord = null
            _isConfigured.value = false

            // Abandon audio focus
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val focusRequest = android.media.AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                    .build()
                audioManager.abandonAudioFocusRequest(focusRequest)
            } else {
                @Suppress("DEPRECATION")
                audioManager.abandonAudioFocus(null)
            }
        } catch (e: Exception) {
            logger.error("Failed to release audio resources", e)
        }
    }

    /**
     * Get current audio route
     */
    fun getAudioRoute(): AudioRoute {
        return when {
            audioManager.isBluetoothScoOn -> AudioRoute.BLUETOOTH
            audioManager.isSpeakerphoneOn -> AudioRoute.SPEAKER
            audioManager.isWiredHeadsetOn -> AudioRoute.HEADSET
            else -> AudioRoute.EARPIECE
        }
    }

    /**
     * Set audio route
     */
    fun setAudioRoute(route: AudioRoute) {
        when (route) {
            AudioRoute.SPEAKER -> {
                audioManager.isSpeakerphoneOn = true
                audioManager.isBluetoothScoOn = false
            }
            AudioRoute.BLUETOOTH -> {
                audioManager.isBluetoothScoOn = true
                audioManager.isSpeakerphoneOn = false
            }
            AudioRoute.EARPIECE -> {
                audioManager.isSpeakerphoneOn = false
                audioManager.isBluetoothScoOn = false
            }
            AudioRoute.HEADSET -> {
                // Headset is automatic when connected
                audioManager.isSpeakerphoneOn = false
                audioManager.isBluetoothScoOn = false
            }
        }
    }

    /**
     * Check if microphone is available
     */
    fun isMicrophoneAvailable(): Boolean {
        return context.packageManager.hasSystemFeature(
            android.content.pm.PackageManager.FEATURE_MICROPHONE
        )
    }

    /**
     * Get recording state
     */
    fun getRecordingState(): Int {
        return audioRecord?.recordingState ?: AudioRecord.RECORDSTATE_STOPPED
    }
}

/**
 * Audio route options
 */
enum class AudioRoute {
    SPEAKER,
    EARPIECE,
    BLUETOOTH,
    HEADSET
}
