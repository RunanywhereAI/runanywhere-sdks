/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Android System TTS module.
 *
 * Wires Android's TextToSpeech service into the commons platform backend using
 * the same callback pattern as Swift's AVSpeechSynthesizer bridge.
 */

package com.runanywhere.sdk.features.TTS.System

import com.runanywhere.sdk.infrastructure.logging.SDKLogger

/**
 * Registers platform callbacks and the built-in `system-tts` catalog entry in
 * commons. Example apps should not construct synthetic ModelInfo values.
 */
object SystemTTSModule {
    private val logger = SDKLogger.tts

    /** Stable registry id for the built-in Android system TTS engine. */
    const val MODEL_ID: String = "system-tts"

    /** Human-readable module name (SystemTTS). */
    const val moduleName: String = "SystemTTS"

    fun register() {
        val result = AndroidSystemTTSPlatform.register()
        logger.debug("SystemTTSModule.register() result=$result")
    }

    fun unregister() {
        val result = AndroidSystemTTSPlatform.unregister()
        logger.debug("SystemTTSModule.unregister() result=$result")
    }
}
