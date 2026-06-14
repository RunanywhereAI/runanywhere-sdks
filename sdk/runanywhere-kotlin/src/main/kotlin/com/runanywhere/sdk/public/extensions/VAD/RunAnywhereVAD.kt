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

import ai.runanywhere.proto.v1.ErrorCategory
import ai.runanywhere.proto.v1.ErrorCode
import ai.runanywhere.proto.v1.VADAudioSource
import ai.runanywhere.proto.v1.VADProcessRequest
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVAD
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAVADOptions
import com.runanywhere.sdk.public.types.RAVADResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map
import okio.ByteString.Companion.toByteString

// MARK: - VAD Operations

private val vadLogger = SDKLogger.vad

/**
 * Swift-parity guard failure: mirrors Swift's plain
 * `SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)`,
 * which is constructed without logging.
 */
private fun notInitializedException(): SDKException =
    SDKException.make(
        code = ErrorCode.ERROR_CODE_NOT_INITIALIZED,
        message = "SDK not initialized",
        category = ErrorCategory.ERROR_CATEGORY_INTERNAL,
        shouldLog = false,
    )

suspend fun RunAnywhere.detectVoiceActivity(
    audioData: ByteArray,
    options: RAVADOptions? = null,
): RAVADResult {
    if (!isInitialized) {
        throw notInitializedException()
    }

    if (audioData.size < 4) {
        throw SDKException.make(
            code = ErrorCode.ERROR_CODE_EMPTY_AUDIO_BUFFER,
            message = "Audio data is empty",
            category = ErrorCategory.ERROR_CATEGORY_COMPONENT,
            shouldLog = false,
        )
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
 *
 * When the underlying detector throws, the failure is surfaced as an
 * error-marked [RAVADResult] (non-empty `error_message`, non-zero
 * `error_code`) and the flow finishes so callers do not silently keep
 * pumping audio into a dead detector.
 */
fun RunAnywhere.streamVAD(
    audio: Flow<ByteArray>,
    options: RAVADOptions? = null,
): Flow<RAVADResult> =
    audio
        .map { chunk -> detectVoiceActivity(chunk, options) }
        .catch { error ->
            if (error is CancellationException) throw error
            val sdkError = SDKException.from(error, ErrorCategory.ERROR_CATEGORY_COMPONENT)
            emit(
                RAVADResult(
                    error_message = "VAD stream failed: ${sdkError.error.message}",
                    error_code = sdkError.code.value,
                ),
            )
        }

suspend fun RunAnywhere.resetVAD() {
    if (!isInitialized) {
        throw notInitializedException()
    }
    CppBridgeVAD.resetLifecycle()
}
