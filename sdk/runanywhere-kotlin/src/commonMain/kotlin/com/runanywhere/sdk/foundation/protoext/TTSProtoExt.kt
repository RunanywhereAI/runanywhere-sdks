/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Extension helpers for the proto-canonical TTS types
 * (ai.runanywhere.proto.v1.{TTSConfiguration, TTSOptions, TTSOutput,
 *  TTSSynthesisMetadata, TTSPhonemeTimestamp, TTSSpeakResult, TTSVoiceInfo}).
 */

package com.runanywhere.sdk.foundation.protoext

import ai.runanywhere.proto.v1.TTSConfiguration
import ai.runanywhere.proto.v1.TTSOptions
import ai.runanywhere.proto.v1.TTSOutput
import ai.runanywhere.proto.v1.TTSPhonemeTimestamp
import ai.runanywhere.proto.v1.TTSSynthesisMetadata

const val TTS_DEFAULT_SAMPLE_RATE: Int = 22050
const val TTS_CD_QUALITY_SAMPLE_RATE: Int = 44100
const val TTS_DEFAULT_VOICE: String = "default"

/**
 * Validate this TTSConfiguration against the canonical ranges in
 * `rac_tts_types.h`.
 *
 * @throws IllegalArgumentException if validation fails
 */
fun TTSConfiguration.validate() {
    require(speaking_rate == 0f || speaking_rate in 0.5f..2.0f) {
        "Invalid speaking rate: $speaking_rate. Must be between 0.5 and 2.0."
    }
    require(pitch == 0f || pitch in 0.5f..2.0f) {
        "Invalid pitch: $pitch. Must be between 0.5 and 2.0."
    }
    require(volume == 0f || volume in 0.0f..1.0f) {
        "Invalid volume: $volume. Must be between 0.0 and 1.0."
    }
}

/** Effective sample rate, falling back to the canonical default (22050 Hz). */
val TTSConfiguration.effectiveSampleRate: Int
    get() = if (sample_rate > 0) sample_rate else TTS_DEFAULT_SAMPLE_RATE

/**
 * Convert a TTSConfiguration to a TTSOptions with matching values.
 * Mirrors the legacy `TTSOptions.from(configuration)` factory.
 */
fun TTSConfiguration.toOptions(): TTSOptions =
    TTSOptions(
        voice = voice,
        language_code = language_code,
        speaking_rate = if (speaking_rate > 0f) speaking_rate else 1f,
        pitch = if (pitch > 0f) pitch else 1f,
        volume = if (volume > 0f) volume else 1f,
        audio_format = audio_format,
        enable_ssml = enable_ssml,
    )

// ============================================================================
// TTSOutput helpers
// ============================================================================

/** Audio size in bytes. */
val TTSOutput.audioSizeBytes: Int
    get() = audio_data.size

/** Whether the output has phoneme timing information. */
val TTSOutput.hasPhonemeTimestamps: Boolean
    get() = phoneme_timestamps.isNotEmpty()

// ============================================================================
// TTSSynthesisMetadata helpers
// ============================================================================

/** Characters processed per second; 0 if processing time is non-positive. */
val TTSSynthesisMetadata.charactersPerSecond: Double
    get() =
        if (processing_time_ms > 0) {
            character_count.toDouble() / (processing_time_ms.toDouble() / 1000.0)
        } else {
            0.0
        }

// ============================================================================
// TTSPhonemeTimestamp helpers
// ============================================================================

/** Duration of the phoneme in milliseconds. */
val TTSPhonemeTimestamp.durationMs: Long
    get() = end_ms - start_ms
