/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for Speech-to-Text operations.
 *
 * Routing decisions live in C++ (rac_router_*). This layer only marshals
 * the request, calls the router, and unpacks the JSON response. There is
 * no Kotlin-side cascade and no model swap on fallback — concurrent
 * components are registered with the router by RouterRegistration.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeRouter
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSTT
import com.runanywhere.sdk.foundation.bridge.extensions.RouterPolicy
import com.runanywhere.sdk.foundation.errors.SDKError
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.STT.STTOptions
import com.runanywhere.sdk.public.extensions.STT.STTOutput
import com.runanywhere.sdk.public.extensions.STT.STTTranscriptionResult
import com.runanywhere.sdk.public.extensions.STT.TranscriptionMetadata
import com.runanywhere.sdk.routing.RoutingPolicy
import com.runanywhere.sdk.routing.isNetworkAvailable

private val sttLogger = SDKLogger.stt

actual suspend fun RunAnywhere.transcribe(audioData: ByteArray): String {
    val result = transcribeWithOptions(audioData, STTOptions())
    return result.text
}

actual suspend fun RunAnywhere.unloadSTTModel() {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    CppBridgeSTT.unload()
}

actual suspend fun RunAnywhere.isSTTModelLoaded(): Boolean {
    return CppBridgeSTT.isLoaded
}

actual val RunAnywhere.currentSTTModelId: String?
    get() = CppBridgeSTT.getLoadedModelId()

actual val RunAnywhere.isSTTModelLoadedSync: Boolean
    get() = CppBridgeSTT.isLoaded

actual suspend fun RunAnywhere.transcribeWithOptions(
    audioData: ByteArray,
    options: STTOptions,
): STTOutput {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val audioLengthSec = estimateAudioLength(audioData.size)
    sttLogger.debug(
        "Transcribing audio: ${audioData.size} bytes (${String.format("%.2f", audioLengthSec)}s)"
    )

    val optionsJson = buildString {
        append('{')
        append("\"sample_rate\":").append(options.sampleRate)
        options.language?.let {
            append(",\"language\":\"").append(escapeJson(it)).append('"')
        }
        append('}')
    }

    val routed = try {
        CppBridgeRouter.runStt(
            isOnline = isNetworkAvailable(),
            policy = options.routingPolicy.toRouterPolicy(),
            preferredFramework = options.preferredFramework?.name?.lowercase(),
            audioData = audioData,
            optionsJson = optionsJson,
        )
    } catch (e: IllegalStateException) {
        throw SDKError.stt(e.message ?: "Router returned no result")
    }

    val confStr = if (routed.confidence.isNaN()) "n/a" else "%.2f".format(routed.confidence)
    sttLogger.info(
        "Routed to '${routed.chosenModuleId}': confidence=$confStr, " +
            "fallback=${routed.wasFallback}, attempts=${routed.attemptCount}, " +
            "text=${routed.text.take(50)}${if (routed.text.length > 50) "..." else ""}"
    )

    return STTOutput(
        text = routed.text,
        confidence = routed.confidence,
        detectedLanguage = routed.language,
        metadata = TranscriptionMetadata(
            modelId = routed.chosenModuleId,
            processingTime = routed.durationMs / 1000.0,
            audioLength = audioLengthSec,
        ),
        routingBackendId = routed.chosenModuleId,
        routingBackendName = routed.chosenModuleId,
        wasFallback = routed.wasFallback,
        primaryConfidence = if (routed.primaryConfidence.isNaN()) null else routed.primaryConfidence,
    )
}

actual suspend fun RunAnywhere.transcribeStream(
    audioData: ByteArray,
    options: STTOptions,
    onPartialResult: (STTTranscriptionResult) -> Unit,
): STTOutput {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    // Streaming intentionally bypasses the router. Streaming-cascade across
    // backends with mid-utterance handoff isn't a meaningful operation —
    // the cascade only fires on a final confidence score. Streaming uses
    // whichever local component is currently loaded.
    val audioLengthSec = estimateAudioLength(audioData.size)

    val config =
        CppBridgeSTT.TranscriptionConfig(
            language = options.language ?: CppBridgeSTT.Language.AUTO,
            sampleRate = options.sampleRate,
        )

    val result =
        CppBridgeSTT.transcribeStream(audioData, config) { partialText, _ ->
            onPartialResult(STTTranscriptionResult(transcript = partialText))
            true
        }

    val metadata =
        TranscriptionMetadata(
            modelId = CppBridgeSTT.getLoadedModelId() ?: "unknown",
            processingTime = result.processingTimeMs / 1000.0,
            audioLength = audioLengthSec,
        )

    return STTOutput(
        text = result.text,
        confidence = result.confidence,
        wordTimestamps = null,
        detectedLanguage = result.language,
        alternatives = null,
        metadata = metadata,
    )
}

actual suspend fun RunAnywhere.processStreamingAudio(samples: FloatArray) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val config = CppBridgeSTT.TranscriptionConfig()
    val audioData = samples.toByteArray()
    CppBridgeSTT.transcribe(audioData, config)
}

actual suspend fun RunAnywhere.stopStreamingTranscription() {
    CppBridgeSTT.cancel()
}

private fun RoutingPolicy.toRouterPolicy(): RouterPolicy = when (this) {
    RoutingPolicy.AUTO                 -> RouterPolicy.AUTO
    RoutingPolicy.LOCAL_ONLY           -> RouterPolicy.LOCAL_ONLY
    RoutingPolicy.CLOUD_ONLY           -> RouterPolicy.CLOUD_ONLY
    RoutingPolicy.PREFER_LOCAL         -> RouterPolicy.PREFER_LOCAL
    RoutingPolicy.PREFER_ACCURACY      -> RouterPolicy.PREFER_ACCURACY
    RoutingPolicy.FRAMEWORK_PREFERRED  -> RouterPolicy.FRAMEWORK_PREFERRED
}

private fun estimateAudioLength(dataSize: Int): Double {
    val bytesPerSample = 2 // 16-bit
    val sampleRate = 16000.0
    val samples = dataSize.toDouble() / bytesPerSample.toDouble()
    return samples / sampleRate
}

private fun FloatArray.toByteArray(): ByteArray {
    val buffer = java.nio.ByteBuffer.allocate(size * 4)
    buffer.order(java.nio.ByteOrder.LITTLE_ENDIAN)
    buffer.asFloatBuffer().put(this)
    return buffer.array()
}

private fun escapeJson(value: String): String =
    value.replace("\\", "\\\\").replace("\"", "\\\"")
