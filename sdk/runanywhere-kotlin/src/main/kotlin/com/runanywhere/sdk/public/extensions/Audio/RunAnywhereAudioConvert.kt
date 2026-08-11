/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public PCM conversion helpers for example apps and host integrations.
 * Thin wrappers over commons `rac_audio_pcm16_to_float32` /
 * `rac_audio_compute_level_normalized` so callers feeding raw Int16
 * microphone PCM into `RunAnywhere.detectVoiceActivity(...)` /
 * `transcribe(...)` / UI meters do not reimplement normalisation.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Commons default dBFS floor for normalized meters (`RAC_AUDIO_LEVEL_FLOOR_DB`). */
const val AUDIO_LEVEL_FLOOR_DB: Float = -60f

// MARK: - PCM Conversion

/**
 * Convert a buffer of Int16 PCM samples to Float32 samples in the range
 * `[-1.0, 1.0]` via `rac_audio_pcm16_to_float32`.
 *
 * @param int16Bytes Raw Int16 PCM samples (little-endian, as captured by
 *   `MediaRecorder` / `AudioRecord`). The bit pattern is preserved verbatim.
 * @return Float32 samples encoded little-endian as a [ByteArray]. The byte
 *   layout matches what `RunAnywhere.detectVoiceActivity(...)` and the STT/VAD
 *   streaming APIs accept as input.
 */
fun RunAnywhere.pcm16ToFloat32(int16Bytes: ByteArray): ByteArray {
    val samples = pcm16ToFloat32Samples(int16Bytes)
    if (samples.isEmpty()) return ByteArray(0)
    val out = ByteBuffer.allocate(samples.size * 4).order(ByteOrder.LITTLE_ENDIAN)
    for (sample in samples) {
        out.putFloat(sample)
    }
    return out.array()
}

/**
 * Convenience overload that returns the normalised samples as a [FloatArray]
 * when callers want to inspect samples directly without going through the SDK's
 * `ByteArray`-based audio surface. Matches Swift
 * `RunAnywhere.pcm16ToFloat32Samples(_:)`.
 */
fun RunAnywhere.pcm16ToFloat32Samples(int16Bytes: ByteArray): FloatArray {
    if (int16Bytes.size < 2) return FloatArray(0)
    return RunAnywhereBridge.racAudioPcm16ToFloat32(int16Bytes)
        ?: throw SDKException.invalidArgument("rac_audio_pcm16_to_float32 failed")
}

/**
 * Normalized meter level in [0, 1] via commons
 * `rac_audio_compute_level_normalized` (RMS → dBFS → floor window).
 * Empty frames return 0.
 */
fun RunAnywhere.computeLevelNormalized(
    samples: FloatArray,
    floorDb: Float = AUDIO_LEVEL_FLOOR_DB,
): Float {
    if (samples.isEmpty()) return 0f
    return RunAnywhereBridge.racAudioComputeLevelNormalized(samples, floorDb)
}

/**
 * PCM16LE → float32 (commons) then normalized meter level (commons).
 * Empty / odd-length frames return 0.
 */
fun RunAnywhere.computeLevelNormalizedFromPcm16Le(
    pcm16le: ByteArray,
    length: Int = pcm16le.size,
    floorDb: Float = AUDIO_LEVEL_FLOOR_DB,
): Float {
    val usable = length.coerceIn(0, pcm16le.size)
    val even = usable - (usable % 2)
    if (even < 2) return 0f
    val bytes = if (even == pcm16le.size) pcm16le else pcm16le.copyOf(even)
    val samples = RunAnywhereBridge.racAudioPcm16ToFloat32(bytes) ?: return 0f
    if (samples.isEmpty()) return 0f
    return RunAnywhereBridge.racAudioComputeLevelNormalized(samples, floorDb)
}
