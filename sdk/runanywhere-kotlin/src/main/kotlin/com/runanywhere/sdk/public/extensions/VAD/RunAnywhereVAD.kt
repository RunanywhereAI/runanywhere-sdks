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

    // Like Swift's detectVoiceActivity, only the raw bytes are set — encoding
    // and sample rate stay at their proto defaults so commons applies the
    // same interpretation for both SDKs.
    val request =
        VADProcessRequest(
            audio = VADAudioSource(audio_data = audioData.toByteString()),
            options = options,
        )

    val result = CppBridgeVAD.processLifecycle(request)

    if (result.is_speech) {
        vadLogger.debug("Speech detected (confidence: ${String.format("%.2f", result.confidence)})")
    }

    return result
}

/**
 * Stream VAD results over a sequence of raw PCM audio chunks. Each chunk in
 * [audio] is processed by [detectVoiceActivity]; the returned flow yields one
 * [RAVADResult] per input chunk. Mirrors Swift's `streamVAD(audio:options:)`.
 */
fun RunAnywhere.streamVAD(
    audio: Flow<ByteArray>,
    options: RAVADOptions? = null,
): Flow<RAVADResult> =
    channelFlow {
        if (!isInitialized) {
            throw SDKException.notInitialized("SDK not initialized")
        }

        audio.collect { chunk ->
            trySendBlocking(detectVoiceActivity(chunk, options))
        }
    }

suspend fun RunAnywhere.resetVAD() {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    CppBridgeVAD.resetLifecycle()
}
