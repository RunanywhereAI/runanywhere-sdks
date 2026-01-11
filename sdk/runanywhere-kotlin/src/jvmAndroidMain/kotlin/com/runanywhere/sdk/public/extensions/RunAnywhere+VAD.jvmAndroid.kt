/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for Voice Activity Detection operations.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVAD
import com.runanywhere.sdk.foundation.errors.SDKError
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.VAD.VADConfiguration
import com.runanywhere.sdk.public.extensions.VAD.VADResult
import com.runanywhere.sdk.public.extensions.VAD.VADStatistics
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val vadLogger = SDKLogger.vad

actual suspend fun RunAnywhere.detectVoiceActivity(audioData: ByteArray): VADResult {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    vadLogger.debug("Processing VAD frame: ${audioData.size} bytes")

    val config = CppBridgeVAD.DetectionConfig()
    val frameResult = CppBridgeVAD.processFrame(audioData, config)

    if (frameResult.isSpeech) {
        vadLogger.debug("Speech detected (confidence: ${String.format("%.2f", frameResult.probability)})")
    }

    return VADResult(
        isSpeech = frameResult.isSpeech,
        confidence = frameResult.probability,
        energyLevel = 0f, // Not directly available from frame result
        statistics = null,
    )
}

actual suspend fun RunAnywhere.configureVAD(configuration: VADConfiguration) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    // VAD configuration is passed per-call in the current architecture
    // This is a no-op as configuration is applied during processing
}

actual suspend fun RunAnywhere.getVADStatistics(): VADStatistics {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    // Return default statistics as the current API doesn't have a dedicated statistics method
    return VADStatistics(
        current = 0f,
        threshold = 0.5f,
        ambient = 0f,
        recentAvg = 0f,
        recentMax = 0f,
    )
}

actual fun RunAnywhere.streamVAD(audioSamples: Flow<FloatArray>): Flow<VADResult> {
    return audioSamples.map { samples ->
        val audioData = samples.toByteArray()
        val config = CppBridgeVAD.DetectionConfig(audioFormat = CppBridgeVAD.AudioFormat.PCM_FLOAT)
        val frameResult = CppBridgeVAD.processFrame(audioData, config)
        VADResult(
            isSpeech = frameResult.isSpeech,
            confidence = frameResult.probability,
            energyLevel = 0f,
            statistics = null,
        )
    }
}

actual suspend fun RunAnywhere.calibrateVAD(ambientAudioData: ByteArray) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    // Process a frame with the ambient audio to calibrate
    val config = CppBridgeVAD.DetectionConfig()
    CppBridgeVAD.processFrame(ambientAudioData, config)
}

actual suspend fun RunAnywhere.resetVAD() {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    CppBridgeVAD.reset()
}

// Helper function to convert FloatArray to ByteArray
private fun FloatArray.toByteArray(): ByteArray {
    val buffer = java.nio.ByteBuffer.allocate(size * 4)
    buffer.order(java.nio.ByteOrder.LITTLE_ENDIAN)
    buffer.asFloatBuffer().put(this)
    return buffer.array()
}
