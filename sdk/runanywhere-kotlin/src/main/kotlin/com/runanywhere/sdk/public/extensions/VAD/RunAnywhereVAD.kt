/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for Voice Activity Detection operations.
 * Calls C++ directly via CppBridge.VAD for all operations.
 * Events are emitted by C++ layer via CppEventBridge.
 *
 * Mirrors Swift RunAnywhere+VAD.swift pattern.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.VADAudioEncoding
import ai.runanywhere.proto.v1.VADAudioSource
import ai.runanywhere.proto.v1.VADProcessRequest
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVAD
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAVADOptions
import com.runanywhere.sdk.public.types.RAVADResult
import kotlinx.coroutines.channels.trySendBlocking
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.flow.collect
import okio.ByteString.Companion.toByteString

// MARK: - VAD Operations

private val vadLogger = SDKLogger.vad

private const val VAD_SAMPLE_RATE_HZ = 16_000

suspend fun RunAnywhere.detectVoiceActivity(
    audioData: ByteArray,
    options: RAVADOptions? = null,
): RAVADResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    if (audioData.size < 2) {
        throw SDKException.operation("Audio data is empty")
    }

    vadLogger.debug("Processing VAD frame: ${audioData.size} bytes")

    val request =
        VADProcessRequest(
            audio =
                VADAudioSource(
                    audio_data = audioData.toByteString(),
                    encoding = VADAudioEncoding.VAD_AUDIO_ENCODING_PCM_S16_LE,
                    sample_rate = VAD_SAMPLE_RATE_HZ,
                ),
            options = options ?: RAVADOptions(),
        )

    val result = CppBridgeVAD.processLifecycle(request)

    if (result.is_speech) {
        vadLogger.debug("Speech detected (confidence: ${String.format("%.2f", result.confidence)})")
    }

    return result
}

fun RunAnywhere.streamVAD(
    audioSamples: Flow<FloatArray>,
    options: RAVADOptions? = null,
): Flow<RAVADResult> =
    channelFlow {
        if (!isInitialized) {
            throw SDKException.notInitialized("SDK not initialized")
        }

        audioSamples.collect { samples ->
            val pcmBytes = samples.toPcm16LeBytes()
            trySendBlocking(detectVoiceActivity(pcmBytes, options))
        }
    }

suspend fun RunAnywhere.resetVAD() {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    CppBridgeVAD.resetLifecycle()
}

/**
 * Convert normalized Float PCM samples in `[-1.0, 1.0]` to little-endian
 * int16 PCM bytes for lifecycle VAD (`VAD_AUDIO_ENCODING_PCM_S16_LE`).
 */
private fun FloatArray.toPcm16LeBytes(): ByteArray {
    val bytes = ByteArray(size * 2)
    var byteIndex = 0
    for (sample in this) {
        val clamped = sample.coerceIn(-1f, 1f)
        val pcm = (clamped * Short.MAX_VALUE.toFloat()).toInt()
        bytes[byteIndex] = (pcm and 0xFF).toByte()
        bytes[byteIndex + 1] = ((pcm shr 8) and 0xFF).toByte()
        byteIndex += 2
    }
    return bytes
}
