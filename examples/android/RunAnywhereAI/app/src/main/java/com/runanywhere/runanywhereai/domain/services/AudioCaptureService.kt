package com.runanywhere.runanywhereai.domain.services

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import com.runanywhere.sdk.features.stt.AudioCaptureManager
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.runBlocking
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.sqrt

/**
 * Service for capturing audio from the device microphone
 *
 * This is a thin wrapper around SDK's AudioCaptureManager for backward compatibility.
 * The actual audio capture is handled by the SDK's platform-specific implementation.
 *
 * iOS Reference: AudioCaptureManager.swift
 */
class AudioCaptureService(
    private val context: Context,
) {
    // Delegate to SDK's AudioCaptureManager
    private val sdkAudioCapture: AudioCaptureManager = AudioCaptureManager.create()

    /**
     * Whether recording is currently active
     */
    val isRecordingState: StateFlow<Boolean>
        get() = sdkAudioCapture.isRecording

    /**
     * Current audio level (0.0 to 1.0) for visualization
     */
    val audioLevel: StateFlow<Float>
        get() = sdkAudioCapture.audioLevel

    /**
     * Check if we have microphone permission
     */
    fun hasRecordPermission(): Boolean {
        return ActivityCompat.checkSelfPermission(
            context,
            Manifest.permission.RECORD_AUDIO,
        ) == PackageManager.PERMISSION_GRANTED
    }

    /**
     * Start capturing audio and emit audio chunks as a Flow
     * Returns PCM audio data at 16kHz, mono, 16-bit
     */
    suspend fun startCapture(): Flow<ByteArray> {
        // Map SDK's AudioChunk to ByteArray for backward compatibility
        return sdkAudioCapture.startRecording().map { chunk -> chunk.data }
    }

    /**
     * Stop audio capture
     */
    fun stopCapture() {
        sdkAudioCapture.stopRecording()
    }

    /**
     * Calculate RMS (Root Mean Square) for audio level visualization
     * Matches iOS implementation for waveform display
     */
    fun calculateRMS(audioData: ByteArray): Float {
        if (audioData.isEmpty()) return 0f

        val shorts =
            ByteBuffer.wrap(audioData)
                .order(ByteOrder.LITTLE_ENDIAN)
                .asShortBuffer()

        var sum = 0.0
        while (shorts.hasRemaining()) {
            val sample = shorts.get().toFloat() / Short.MAX_VALUE
            sum += sample * sample
        }

        return sqrt(sum / (audioData.size / 2)).toFloat()
    }

    /**
     * Get the current recording state
     */
    fun isRecording(): Boolean = isRecordingState.value

    /**
     * Clean up resources
     */
    fun release() {
        runBlocking {
            sdkAudioCapture.cleanup()
        }
    }
}
