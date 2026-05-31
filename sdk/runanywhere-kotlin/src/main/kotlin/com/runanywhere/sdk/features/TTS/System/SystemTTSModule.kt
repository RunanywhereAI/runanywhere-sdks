/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Built-in System TTS module for Android, mirroring iOS's
 * `Features/TTS/System/SystemTTSModule.swift`. Registers a synthetic
 * ModelInfo into the proto registry so that `system-tts` resolves
 * through the same Model Selection path as downloadable voices.
 */

package com.runanywhere.sdk.features.TTS.System

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelFormat
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.extensions.registerModelInternal
import com.runanywhere.sdk.public.types.RAModelInfo

/**
 * Built-in Android system TTS module.
 *
 * Registers a `system-tts` ModelInfo as a built-in, always-downloaded
 * registry entry so that the platform TTS provider (driven by C++
 * platform callbacks) participates in the model selection UI without
 * requiring example apps to construct synthetic ModelInfo values
 * inline. Mirrors iOS's `SystemTTS` namespace + platform backend
 * registration in `CppBridge+Platform.swift`.
 */
object SystemTTSModule {
    private val logger = SDKLogger.tts

    /** Stable registry id for the built-in Android system TTS engine. */
    const val MODEL_ID: String = "system-tts"

    /** Human-readable module name (SystemTTS). */
    const val moduleName: String = "SystemTTS"

    suspend fun register() {
        logger.info("Registering System TTS as a built-in registry entry")
        registerModelInternal(
            RAModelInfo(
                id = MODEL_ID,
                name = "System TTS",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS,
                category = ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
                format = ModelFormat.MODEL_FORMAT_PROPRIETARY,
                built_in = true,
                is_downloaded = true,
            ),
        )
    }

    suspend fun unregister() {
        // Registry does not currently support entry removal; the C++
        // platform TTS callbacks remain wired through SDK shutdown.
        logger.debug("SystemTTSModule.unregister() is a no-op (registry has no remove API)")
    }
}
