/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Sarvam AI cloud STT backend for hybrid routing.
 */
package com.runanywhere.sdk.backends.stt

import com.runanywhere.sdk.cloud.sarvam.Sarvam
import com.runanywhere.sdk.cloud.sarvam.SarvamBridge
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
 * Sarvam AI cloud STT backend.
 *
 * Lower priority than Whisper — used as fallback when:
 * - Local model is not loaded
 * - Caller sets CLOUD_ONLY policy
 * - Caller forces SARVAM framework via preferredFramework
 *
 * Requires network and a configured API key (both are hard gates).
 */
class SarvamSTTBackend : STTBackend {

    override fun descriptors() = listOf(
        BackendDescriptor(
            moduleId = "sarvam-cloud",
            moduleName = "Sarvam AI (Cloud)",
            capability = SDKComponent.STT,
            inferenceFramework = InferenceFramework.SARVAM,
            basePriority = 80,
            conditions = listOf(
                RoutingCondition.NetworkRequired,
                RoutingCondition.Custom(
                    description = "Sarvam API key configured",
                    check = { SarvamBridge.hasApiKey() },
                ),
                RoutingCondition.QualityTier(BackendQuality.HIGH),
                RoutingCondition.CostModel(costPerMinuteCents = 2.5f),
            ),
        )
    )

    override suspend fun transcribe(audioData: ByteArray, options: STTOptions): STTOutput {
        // Ensure Sarvam model is loaded — it may not be if we're coming from a cascade
        val loadedId = CppBridgeSTT.getLoadedModelId()
        if (loadedId == null || !loadedId.startsWith("sarvam:", ignoreCase = true)) {
            val loadResult = CppBridgeSTT.loadModel(
                modelPath = "sarvam:saarika:v2.5",
                modelId = "sarvam:saarika:v2.5",
                modelName = "Sarvam Saarika v2.5",
            )
            if (loadResult != 0) {
                throw Exception("Failed to load Sarvam model: error $loadResult")
            }
        }

        // Sarvam requires Indian locale codes (e.g. "en-IN", "hi-IN").
        // Map bare language codes to their Indian variants.
        val sarvamLanguage = mapToSarvamLanguage(options.language ?: "hi-IN")
        val config = CppBridgeSTT.TranscriptionConfig(
            language = sarvamLanguage,
            sampleRate = options.sampleRate,
        )
        val result = CppBridgeSTT.transcribe(audioData, config)
        val audioLengthSec = audioData.size / (2.0 * options.sampleRate)
        return STTOutput(
            text = result.text,
            confidence = result.confidence,
            metadata = TranscriptionMetadata(
                modelId = "sarvam:saarika:v2.5",
                processingTime = result.processingTimeMs / 1000.0,
                audioLength = audioLengthSec,
            ),
        )
    }

    companion object {
        private val SARVAM_LANGUAGE_MAP = mapOf(
            "en" to "en-IN",
            "hi" to "hi-IN",
            "bn" to "bn-IN",
            "ta" to "ta-IN",
            "te" to "te-IN",
            "mr" to "mr-IN",
            "kn" to "kn-IN",
            "gu" to "gu-IN",
            "ml" to "ml-IN",
            "pa" to "pa-IN",
            "or" to "od-IN",
            "ur" to "ur-IN",
            "auto" to "unknown",
        )

        fun mapToSarvamLanguage(language: String): String {
            // Already a Sarvam locale code (contains "-IN")
            if (language.contains("-IN")) return language
            if (language == "unknown") return language
            return SARVAM_LANGUAGE_MAP[language.lowercase()] ?: "en-IN"
        }
    }
}
