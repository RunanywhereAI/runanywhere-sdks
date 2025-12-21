package com.runanywhere.sdk.features.stt

import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.emptyFlow

/**
 * Platform-specific factory for Native (iOS/macOS)
 */
actual fun createAudioCaptureManager(): AudioCaptureManager = NativeAudioCaptureManager()

/**
 * Native (iOS/macOS) stub implementation of AudioCaptureManager.
 *
 * For iOS, use the Swift SDK's AudioCaptureManager directly, which provides
 * full AVAudioEngine-based audio capture. This KMP implementation is a stub
 * that defers to native Swift code.
 *
 * To use audio capture on iOS:
 * 1. Use the Swift SDK's AudioCaptureManager
 * 2. Or implement native interop to call AVAudioEngine from Kotlin/Native
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/STT/Services/AudioCaptureManager.swift
 */
class NativeAudioCaptureManager : AudioCaptureManager {
    private val logger = SDKLogger("AudioCapture")

    private val _isRecording = MutableStateFlow(false)
    override val isRecording: StateFlow<Boolean> = _isRecording.asStateFlow()

    private val _audioLevel = MutableStateFlow(0.0f)
    override val audioLevel: StateFlow<Float> = _audioLevel.asStateFlow()

    override val targetSampleRate: Int = 16000

    init {
        logger.info("NativeAudioCaptureManager initialized (stub implementation)")
        logger.warning("For full audio capture on iOS, use the Swift SDK's AudioCaptureManager")
    }

    override suspend fun requestPermission(): Boolean {
        // On iOS, permission must be requested through Swift
        // This is a stub - actual implementation requires AVAudioSession
        logger.warning("Audio permission request requires Swift SDK integration")
        return false
    }

    override suspend fun hasPermission(): Boolean {
        // This is a stub - actual implementation requires AVAudioSession
        logger.warning("Audio permission check requires Swift SDK integration")
        return false
    }

    override suspend fun startRecording(): Flow<AudioChunk> {
        logger.error("Audio recording on iOS requires Swift SDK's AudioCaptureManager")
        throw AudioCaptureError.InitializationFailed(
            "Native audio capture not available in KMP. Use Swift SDK's AudioCaptureManager for iOS.",
        )
    }

    override fun stopRecording() {
        _isRecording.value = false
        _audioLevel.value = 0.0f
    }

    override suspend fun cleanup() {
        stopRecording()
    }
}
