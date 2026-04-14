/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for Speech-to-Text operations.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSTT
import com.runanywhere.sdk.foundation.errors.SDKError
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.routing.isNetworkAvailable
import com.runanywhere.sdk.public.extensions.STT.STTOptions
import com.runanywhere.sdk.public.extensions.STT.STTOutput
import com.runanywhere.sdk.public.extensions.STT.STTTranscriptionResult
import com.runanywhere.sdk.public.extensions.STT.TranscriptionMetadata
import com.runanywhere.sdk.routing.HybridRouterRegistry
import com.runanywhere.sdk.routing.RoutingContext

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
    sttLogger.debug("Transcribing audio: ${audioData.size} bytes (${String.format("%.2f", audioLengthSec)}s)")

    val context = RoutingContext(
        isNetworkAvailable = isNetworkAvailable(),
        routingPolicy = options.routingPolicy,
        preferredFramework = options.preferredFramework,
    )

    val candidates = HybridRouterRegistry.resolveSTT(context)
    if (candidates.isEmpty()) {
        throw SDKError.stt(
            "No STT backend available (network=${context.isNetworkAvailable}, policy=${context.routingPolicy})"
        )
    }

    val confidenceThreshold = 0.5f

    var lastError: Throwable? = null
    for ((index, descriptor) in candidates.withIndex()) {
        val backend = HybridRouterRegistry.sttBackendFor(descriptor.moduleId) ?: continue
        try {
            sttLogger.debug("Routing STT to '${descriptor.moduleId}'")
            val result = backend.transcribe(audioData, options)

            // Mock confidence score for now — replace with real inference confidence later
            val mockConfidence = kotlin.random.Random.nextFloat()
            val resultWithRouting = result.copy(
                routingBackendId = descriptor.moduleId,
                routingBackendName = descriptor.moduleName,
                confidence = mockConfidence,
            )

            sttLogger.info(
                "Transcription via '${descriptor.moduleId}': " +
                    "confidence=${"%.2f".format(mockConfidence)}, " +
                    "text=${result.text.take(50)}${if (result.text.length > 50) "..." else ""}"
            )

            // Confidence cascade: if local backend scored below threshold and there
            // are cloud fallbacks available, hand off to the next candidate.
            if (mockConfidence < confidenceThreshold && descriptor.isLocalOnly && index < candidates.lastIndex) {
                sttLogger.info(
                    "Confidence ${"%.2f".format(mockConfidence)} < $confidenceThreshold — " +
                        "cascading to next backend"
                )
                val fallbackDescriptor = candidates[index + 1]
                val fallbackBackend = HybridRouterRegistry.sttBackendFor(fallbackDescriptor.moduleId)
                if (fallbackBackend != null) {
                    // Remember the local model so we can restore it after cloud fallback
                    val previousModelId = CppBridgeSTT.getLoadedModelId()
                    val previousModelPath = CppBridgeSTT.getLoadedModelPath()
                    try {
                        sttLogger.debug("Fallback routing to '${fallbackDescriptor.moduleId}'")
                        val fallbackResult = fallbackBackend.transcribe(audioData, options)
                        // Restore the local model after cloud fallback
                        restoreLocalModel(previousModelId, previousModelPath)
                        return fallbackResult.copy(
                            routingBackendId = fallbackDescriptor.moduleId,
                            routingBackendName = fallbackDescriptor.moduleName,
                            wasFallback = true,
                            primaryConfidence = mockConfidence,
                        )
                    } catch (e: Exception) {
                        sttLogger.warn("Fallback '${fallbackDescriptor.moduleId}' failed: ${e.message}")
                        // Restore the local model even on failure
                        restoreLocalModel(previousModelId, previousModelPath)
                    }
                }
            }

            return resultWithRouting
        } catch (e: Exception) {
            sttLogger.warn("Backend '${descriptor.moduleId}' failed, trying next: ${e.message}")
            lastError = e
        }
    }

    throw lastError ?: SDKError.stt("All STT backends failed")
}

actual suspend fun RunAnywhere.transcribeStream(
    audioData: ByteArray,
    options: STTOptions,
    onPartialResult: (STTTranscriptionResult) -> Unit,
): STTOutput {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val audioLengthSec = estimateAudioLength(audioData.size)

    val config =
        CppBridgeSTT.TranscriptionConfig(
            language = options.language ?: CppBridgeSTT.Language.AUTO,
            sampleRate = options.sampleRate,
        )

    val result =
        CppBridgeSTT.transcribeStream(audioData, config) { partialText, isFinal ->
            onPartialResult(STTTranscriptionResult(transcript = partialText))
            true // Continue processing
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

// Restore local model after cloud fallback so next request can route locally again
private fun restoreLocalModel(modelId: String?, modelPath: String?) {
    if (modelId != null && modelPath != null &&
        (modelId.contains("whisper", ignoreCase = true) || modelId.contains("sherpa", ignoreCase = true))
    ) {
        try {
            sttLogger.debug("Restoring local model: $modelId")
            CppBridgeSTT.loadModel(modelPath = modelPath, modelId = modelId, modelName = modelId)
        } catch (e: Exception) {
            sttLogger.warn("Failed to restore local model: ${e.message}")
        }
    }
}

// Private helper
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
