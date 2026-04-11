/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Local Whisper STT backend for hybrid routing.
 */
package com.runanywhere.sdk.backends.stt

import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.core.types.SDKComponent
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSTT
import com.runanywhere.sdk.public.extensions.STT.STTOptions
import com.runanywhere.sdk.public.extensions.STT.STTOutput
import com.runanywhere.sdk.public.extensions.STT.TranscriptionMetadata
import com.runanywhere.sdk.routing.BackendDescriptor
import com.runanywhere.sdk.routing.BackendQuality
import com.runanywhere.sdk.routing.RoutingCondition
import com.runanywhere.sdk.routing.STTBackend

/**
 * Local Whisper STT backend via C++ bridge (Sherpa-ONNX / WhisperCPP).
 *
 * High priority by default. Excluded only when the local model is not loaded.
 * No network required, no cost.
 */
class WhisperSTTBackend : STTBackend {

    override fun descriptors() = listOf(
        BackendDescriptor(
            moduleId = "whisper-local",
            moduleName = "Whisper (Local)",
            capability = SDKComponent.STT,
            inferenceFramework = InferenceFramework.ONNX,
            basePriority = 200,
            conditions = listOf(
                RoutingCondition.LocalOnly,
                RoutingCondition.ModelAvailability(
                    modelId = "whisper",
                    isModelLoaded = {
                        val id = CppBridgeSTT.getLoadedModelId() ?: return@ModelAvailability false
                        id.contains("whisper", ignoreCase = true) ||
                            id.contains("sherpa", ignoreCase = true)
                    },
                ),
                RoutingCondition.QualityTier(BackendQuality.STANDARD),
                RoutingCondition.CostModel(costPerMinuteCents = 0f),
            ),
        )
    )

    override suspend fun transcribe(audioData: ByteArray, options: STTOptions): STTOutput {
        val config = CppBridgeSTT.TranscriptionConfig(
            language = options.language ?: CppBridgeSTT.Language.AUTO,
            sampleRate = options.sampleRate,
        )
        val result = CppBridgeSTT.transcribe(audioData, config)
        val audioLengthSec = audioData.size / (2.0 * options.sampleRate)
        return STTOutput(
            text = result.text,
            confidence = result.confidence,
            detectedLanguage = result.language,
            metadata = TranscriptionMetadata(
                modelId = CppBridgeSTT.getLoadedModelId() ?: "whisper",
                processingTime = result.processingTimeMs / 1000.0,
                audioLength = audioLengthSec,
            ),
        )
    }
}
