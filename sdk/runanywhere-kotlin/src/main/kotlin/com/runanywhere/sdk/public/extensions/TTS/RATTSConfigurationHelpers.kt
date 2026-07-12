/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Ergonomic helpers for canonical TTS proto types.
 *
 * defaults() live in generated/convenience/RAConvenience.kt, emitted from the
 * canonical IDL annotations. This file contains only Kotlin-specific computed
 * helpers and result adapters.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.TTSPhonemeTimestamp
import ai.runanywhere.proto.v1.TTSSpeakResult
import ai.runanywhere.proto.v1.TTSSynthesisMetadata
import com.runanywhere.sdk.public.types.RATTSOutput

// MARK: - TTSPhonemeTimestamp

/**
 * Construct a [TTSPhonemeTimestamp] from seconds-based timing values,
 * mirroring Swift's `RATTSPhonemeTimestamp(phoneme:startTime:endTime:)`.
 */
fun TTSPhonemeTimestamp.Companion.create(
    phoneme: String,
    startTime: Double,
    endTime: Double,
): TTSPhonemeTimestamp =
    TTSPhonemeTimestamp(
        phoneme = phoneme,
        start_ms = (startTime * 1000.0).toLong(),
        end_ms = (endTime * 1000.0).toLong(),
    )

/** Start time in seconds. */
val TTSPhonemeTimestamp.startTime: Double
    get() = start_ms.toDouble() / 1000.0

/** End time in seconds. */
val TTSPhonemeTimestamp.endTime: Double
    get() = end_ms.toDouble() / 1000.0

/** Duration in seconds (clamped to >= 0). */
val TTSPhonemeTimestamp.duration: Double
    get() = (endTime - startTime).coerceAtLeast(0.0)

// MARK: - TTSSynthesisMetadata

/** Processing time in seconds. */
val TTSSynthesisMetadata.processingTime: Double
    get() = processing_time_ms.toDouble() / 1000.0

/** Audio duration in seconds. */
val TTSSynthesisMetadata.audioDuration: Double
    get() = audio_duration_ms.toDouble() / 1000.0

// MARK: - TTSOutput

/** Audio duration in seconds. */
val RATTSOutput.duration: Double
    get() = duration_ms.toDouble() / 1000.0

/** Wall-clock timestamp in milliseconds since the Unix epoch. */
val RATTSOutput.timestampEpochMs: Long
    get() = timestamp_ms

// MARK: - TTSSpeakResult

/**
 * Construct a [TTSSpeakResult] copying audio metadata from a [TTSOutput].
 * Mirrors Swift's `RATTSSpeakResult(output:)`.
 */
fun TTSSpeakResult.Companion.fromOutput(output: RATTSOutput): TTSSpeakResult =
    TTSSpeakResult(
        audio_format = output.audio_format,
        sample_rate = output.sample_rate,
        duration_ms = output.duration_ms,
        audio_size_bytes =
            if (output.audio_size_bytes > 0L) {
                output.audio_size_bytes
            } else {
                output.audio_data.size.toLong()
            },
        metadata = output.metadata,
        timestamp_ms = output.timestamp_ms,
    )

/** Audio duration in seconds. */
val TTSSpeakResult.duration: Double
    get() = duration_ms.toDouble() / 1000.0

/** Wall-clock timestamp in milliseconds since the Unix epoch. */
val TTSSpeakResult.timestampEpochMs: Long
    get() = timestamp_ms
