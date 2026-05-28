/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public PCM conversion helpers for example apps and host integrations.
 * Mirrors Swift `RAAudioConvert.swift` (and the commons
 * `rac_audio_pcm16_to_float32` inline routine) so callers feeding raw Int16
 * microphone PCM into `RunAnywhere.detectVoiceActivity(...)` / `transcribe(...)`
 * do not need to reimplement the divide-by-32768.0 normalisation, matching the
 * canonical commons audio normalisation contract.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.RunAnywhere
import java.nio.ByteBuffer
import java.nio.ByteOrder

// MARK: - PCM Conversion

/**
 * Convert a buffer of Int16 PCM samples to Float32 samples in the range
 * `[-1.0, 1.0]`. Matches Swift `RunAnywhere.pcm16ToFloat32(_:)` and commons
 * `rac_audio_pcm16_to_float32` (divides each sample by `32768.0`).
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
    val int16Count = int16Bytes.size / 2
    if (int16Count == 0) return FloatArray(0)
    val input = ByteBuffer.wrap(int16Bytes).order(ByteOrder.LITTLE_ENDIAN)
    return FloatArray(int16Count) { input.short.toFloat() / 32768.0f }
}
