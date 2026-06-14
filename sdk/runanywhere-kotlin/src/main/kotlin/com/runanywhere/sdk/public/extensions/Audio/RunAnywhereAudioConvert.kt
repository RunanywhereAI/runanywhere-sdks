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

/**
 * Wrap raw 16-bit mono PCM samples in a canonical 44-byte WAV (RIFF)
 * container: `RIFF` + `fmt ` (16-byte PCM chunk, format tag 1, 1 channel)
 * + `data`. Matches Swift `RunAnywhere.pcm16ToWav(_:sampleRate:)`.
 *
 * Use this when a consumer needs a self-describing audio container rather
 * than headerless PCM — e.g. cloud STT providers that upload the bytes as
 * an `audio/wav` file part. `HybridSTTRouter.transcribe` applies it
 * automatically to raw PCM16 input.
 *
 * @param int16Bytes Raw Int16 mono PCM samples (little-endian, as captured
 *   by `AudioRecord`). The sample bytes are copied verbatim after the header.
 * @param sampleRate Capture sample rate in Hz (e.g. 16000).
 * @return The same samples prefixed with a WAV header.
 */
fun RunAnywhere.pcm16ToWav(int16Bytes: ByteArray, sampleRate: Int): ByteArray {
    val pcmFormatTag: Short = 1
    val channels: Short = 1
    val bitsPerSample: Short = 16
    val blockAlign = (channels * bitsPerSample / 8).toShort()
    val byteRate = sampleRate * blockAlign
    val fmtChunkSize = 16
    val wav = ByteBuffer.allocate(44 + int16Bytes.size).order(ByteOrder.LITTLE_ENDIAN)
    wav.put("RIFF".toByteArray(Charsets.US_ASCII))
    wav.putInt(36 + int16Bytes.size)
    wav.put("WAVE".toByteArray(Charsets.US_ASCII))
    wav.put("fmt ".toByteArray(Charsets.US_ASCII))
    wav.putInt(fmtChunkSize)
    wav.putShort(pcmFormatTag)
    wav.putShort(channels)
    wav.putInt(sampleRate)
    wav.putInt(byteRate)
    wav.putShort(blockAlign)
    wav.putShort(bitsPerSample)
    wav.put("data".toByteArray(Charsets.US_ASCII))
    wav.putInt(int16Bytes.size)
    wav.put(int16Bytes)
    return wav.array()
}
