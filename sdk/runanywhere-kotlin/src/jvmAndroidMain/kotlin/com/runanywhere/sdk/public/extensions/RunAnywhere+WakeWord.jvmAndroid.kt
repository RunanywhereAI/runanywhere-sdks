/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for Wake Word detection (P2 B11).
 *
 * The native `rac_wake_word_*` C ABI in runanywhere-commons is
 * currently stubbed (returns RAC_ERROR_FEATURE_NOT_AVAILABLE) and the
 * Kotlin JNI bridge (`RunAnywhereBridge`) does not yet expose
 * `racWakeWordLoad / racWakeWordDetect / racWakeWordUnload`. These
 * actuals log a warning and throw `notImplemented` so apps get a
 * clear signal rather than a link-time failure. Once the JNI thunks
 * land, switch the bodies to call them directly — the public signature
 * will stay identical.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere

private val wakeWordLogger = SDKLogger("RunAnywhere.WakeWord")

actual suspend fun RunAnywhere.loadWakeWordModel(modelPath: String) {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    wakeWordLogger.warning(
        "loadWakeWordModel($modelPath): wake-word not wired in commons (rac_wake_word_* is stubbed)",
    )
    throw SDKException.notImplemented(
        "Wake-word detection is not yet wired in runanywhere-commons (rac_wake_word_* is stubbed).",
    )
}

actual suspend fun RunAnywhere.detectWakeWord(audio: ByteArray): Boolean {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    wakeWordLogger.warning(
        "detectWakeWord(${audio.size} bytes): wake-word not wired in commons",
    )
    throw SDKException.notImplemented(
        "Wake-word detection is not yet wired in runanywhere-commons (rac_wake_word_* is stubbed).",
    )
}

actual suspend fun RunAnywhere.unloadWakeWordModel() {
    if (!isInitialized) return
    // rac_wake_word_destroy is NULL-safe; mirror that contract and no-op
    // until the JNI thunk is wired.
    wakeWordLogger.debug("unloadWakeWordModel: no-op (wake-word not wired in commons)")
}
