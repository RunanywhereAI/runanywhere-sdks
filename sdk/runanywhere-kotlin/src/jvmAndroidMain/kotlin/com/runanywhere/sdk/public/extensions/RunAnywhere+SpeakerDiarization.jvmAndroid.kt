/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for Speaker Diarization (B12, §8).
 *
 * The C ABI (rac_speaker_diarization_init / _process / _destroy) exists in
 * runanywhere-commons but is currently a stub returning
 * RAC_ERROR_FEATURE_NOT_AVAILABLE. There is also no JNI bridge yet
 * (CppBridgeSpeakerDiarization), so this actual:
 *   1. Logs a warning on every call so it's obvious the feature is stubbed.
 *   2. Returns empty / false for read ops.
 *   3. Throws a clear `featureNotAvailable` on load ops so callers can
 *      detect the stub state without crashes.
 *
 * TODO(diarization): When commons replaces the stub with a real
 * implementation, add a `CppBridgeSpeakerDiarization` object (in
 * `foundation/bridge/extensions/`) that wraps the JNI functions and
 * replace the bodies below with real calls. The public expect/actual
 * signatures in commonMain stay the same.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere

private val diarizationLogger = SDKLogger("SpeakerDiarization")

actual suspend fun RunAnywhere.loadDiarizationModel(modelPath: String) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    diarizationLogger.warning(
        "loadDiarizationModel: feature not yet available in commons (stub). modelPath=$modelPath",
    )
    throw SDKException.notImplemented(
        "Speaker diarization is not yet integrated in runanywhere-commons.",
    )
}

actual val RunAnywhere.isDiarizationLoaded: Boolean
    get() = false

actual suspend fun RunAnywhere.diarize(audio: ByteArray): List<SpeakerSegment> {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    diarizationLogger.warning(
        "diarize: feature not yet available in commons (stub). Returning empty segments. " +
            "audioBytes=${audio.size}",
    )
    return emptyList()
}

actual suspend fun RunAnywhere.unloadDiarization() {
    // No resources to release while the feature is stubbed.
    diarizationLogger.debug("unloadDiarization: no-op (feature stubbed)")
}
