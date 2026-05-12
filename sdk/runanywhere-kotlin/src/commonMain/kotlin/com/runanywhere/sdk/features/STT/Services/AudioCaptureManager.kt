/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * AudioCaptureManager — shared audio capture utility for STT features.
 *
 * Ports the iOS `AudioCaptureManager.swift` (Features/STT/Services) to Kotlin
 * Multiplatform. Captures audio at 16 kHz mono 16-bit PCM (the standard input
 * format for speech recognition models like Whisper / Sherpa-ONNX) and emits
 * raw PCM byte arrays to a callback supplied by the consumer.
 *
 * ## API parity with Swift
 * | Swift                                | Kotlin                              |
 * |--------------------------------------|-------------------------------------|
 * | `requestPermission() async -> Bool`  | `suspend fun requestPermission()`   |
 * | `startRecording(onAudioData:)`       | `suspend fun startRecording(...)`   |
 * | `stopRecording()`                    | `fun stopRecording()`               |
 * | `activateAudioSession()`             | `suspend fun activateAudioSession()`|
 * | `deactivateAudioSession()`           | `suspend fun deactivateAudioSession()` |
 * | `AudioCaptureError` enum             | `sealed class AudioCaptureError`    |
 *
 * ## Concurrency
 * All callbacks are dispatched from the capture background thread. The class
 * is not thread-safe for concurrent `startRecording` / `stopRecording` calls;
 * callers should serialize lifecycle transitions.
 *
 * ## Usage
 * ```kotlin
 * val capture = AudioCaptureManager()
 * if (capture.requestPermission()) {
 *     capture.startRecording { pcmBytes ->
 *         // Feed pcmBytes to your STT service
 *     }
 *     // ...
 *     capture.stopRecording()
 * }
 * ```
 */

package com.runanywhere.sdk.features.STT.Services

/**
 * Manages microphone audio capture for STT services.
 *
 * Each platform actual is responsible for:
 *  - Requesting microphone permission (Android: `RECORD_AUDIO`; JVM: always granted)
 *  - Configuring the platform audio session (Android: `AudioManager.requestAudioFocus`; JVM: no-op)
 *  - Reading PCM 16-bit mono samples at [TARGET_SAMPLE_RATE] from the default input device
 *  - Delivering the raw bytes to the consumer's `onAudioData` callback
 *
 * Errors thrown from `startRecording` are wrapped in [com.runanywhere.sdk.foundation.errors.SDKException].
 */
expect class AudioCaptureManager() {
    /** Whether a capture session is currently active. Updated from the background thread. */
    val isRecording: Boolean

    /** Most recent normalized audio level (0.0 – 1.0). Updated by the capture thread. */
    val audioLevel: Float

    /**
     * Request microphone permission.
     *
     * - Android: returns `true` if `RECORD_AUDIO` is already granted; the consumer
     *   app is responsible for actually showing the runtime permission prompt via
     *   `ActivityCompat.requestPermissions` because that requires an `Activity`.
     * - JVM: always returns `true`.
     */
    suspend fun requestPermission(): Boolean

    /**
     * Start capturing audio. Throws [com.runanywhere.sdk.foundation.errors.SDKException]
     * on failure (permission denied, no input device, format conversion failure, etc.).
     *
     * @param onAudioData callback invoked for every captured PCM 16-bit mono chunk.
     *                    Called from the capture background thread.
     */
    suspend fun startRecording(onAudioData: (ByteArray) -> Unit)

    /** Stop a running capture session. Safe to call when not recording (no-op). */
    fun stopRecording()

    /**
     * Activate the platform audio session without starting capture. Useful for
     * keep-alive flows (background recording on iOS). On Android this requests
     * audio focus; on JVM this is a no-op.
     */
    suspend fun activateAudioSession()

    /** Deactivate the platform audio session. */
    suspend fun deactivateAudioSession()
}

/**
 * Errors raised by [AudioCaptureManager]. Mirrors Swift's `AudioCaptureError`
 * enum. Wrapped in `SDKException` (category `ERROR_CATEGORY_COMPONENT`,
 * code `ERROR_CODE_*` per case) before being thrown.
 */
sealed class AudioCaptureError(
    val description: String,
) {
    /** Microphone permission was denied. */
    data object PermissionDenied : AudioCaptureError("Microphone permission denied")

    /** PCM format conversion (channel / sample rate) failed. */
    data object FormatConversionFailed : AudioCaptureError("Failed to convert audio format")

    /** The capture engine failed to start (already in use, hardware error, etc.). */
    data class EngineStartFailed(
        val reason: String? = null,
    ) : AudioCaptureError(
            if (reason != null) "Failed to start audio engine: $reason" else "Failed to start audio engine",
        )

    /** No audio input device is available on this host. */
    data object NoInputDevice : AudioCaptureError("No audio input device available")
}

/**
 * Default audio capture parameters. Mirrors the Swift `targetSampleRate`
 * constant and the iOS/Android example app conventions: 16 kHz mono 16-bit PCM.
 */
internal object AudioCaptureConstants {
    /** Target sample rate in Hz. Matches `RAC_STT_DEFAULT_SAMPLE_RATE` in commons. */
    const val TARGET_SAMPLE_RATE: Int = 16000

    /** Mono = 1 channel. */
    const val CHANNEL_COUNT: Int = 1

    /** 16-bit PCM = 2 bytes per sample. */
    const val BYTES_PER_SAMPLE: Int = 2

    /** Emit chunks roughly every 100 ms to match the Android example. */
    const val CHUNK_DURATION_MS: Int = 100
}
