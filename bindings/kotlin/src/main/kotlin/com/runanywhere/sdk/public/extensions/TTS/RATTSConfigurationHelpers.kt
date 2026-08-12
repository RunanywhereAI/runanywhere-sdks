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

import ai.runanywhere.proto.v1.TTSSpeakResult
import com.runanywhere.sdk.public.types.RATTSOutput

// `TTSPhonemeTimestamp` is deleted outright (idl/tts_options.proto,
// `TTSOutput` reserved 5 "phoneme_timestamps" -- never produced) and
// `TTSSynthesisMetadata.audio_duration_ms` is likewise reserved (== the
// parent `duration_ms`), so both helper groups built on them are dropped
// rather than rehomed onto fields that no longer exist. Matches Swift's
// `RATTSConfiguration+Helpers.swift`, which carries neither any more.

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
 *
 * `TTSOutput.audio_size_bytes` is deleted outright (idl/tts_options.proto);
 * `TTSSpeakResult.audio_size_bytes` (this message, a distinct field)
 * survives, so it is derived from the raw audio buffer length instead of a
 * source field that no longer exists. Mirrors Swift's
 * `RATTSSpeakResult(output:)`.
 */
fun TTSSpeakResult.Companion.fromOutput(output: RATTSOutput): TTSSpeakResult =
    TTSSpeakResult(
        audio_format = output.audio_format,
        sample_rate = output.sample_rate,
        duration_ms = output.duration_ms,
        audio_size_bytes = output.audio_data.size.toLong(),
        metadata = output.metadata,
        timestamp_ms = output.timestamp_ms,
    )

/** Audio duration in seconds. */
val TTSSpeakResult.duration: Double
    get() = duration_ms.toDouble() / 1000.0

/** Wall-clock timestamp in milliseconds since the Unix epoch. */
val TTSSpeakResult.timestampEpochMs: Long
    get() = timestamp_ms
