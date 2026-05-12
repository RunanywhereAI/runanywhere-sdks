/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM (desktop) counterpart to the Android `SystemTTSModule`.
 * Maintains module-API contract symmetry with the Android source set
 * — JVM hosts have no platform-provided TTS engine, so [register] is
 * a logged no-op.
 */

package com.runanywhere.sdk.features.TTS.System

import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.RunAnywhereModule

/**
 * No-op JVM desktop counterpart to Android's [SystemTTSModule].
 *
 * Desktop JVM hosts do not ship a platform TTS engine that the C++
 * backend can drive (Android relies on `android.speech.tts.TextToSpeech`
 * via callbacks), so [register] only emits a debug log and refuses to
 * seed a synthetic `system-tts` registry entry.
 */
object JvmSystemTTSModule : RunAnywhereModule {
    private val logger = SDKLogger.tts

    override val moduleName: String = "SystemTTS"

    override suspend fun register() {
        logger.debug(
            "JvmSystemTTSModule.register() is a no-op — JVM desktop hosts have no system TTS engine",
        )
    }

    override suspend fun unregister() {
        // No-op: register did not seed any registry state.
    }
}
