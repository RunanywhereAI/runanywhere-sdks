/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Ergonomic helpers for canonical TTS proto types.
 *
 * Mirrors Swift RATTSConfiguration+Helpers.swift exactly. Pure ergonomics —
 * no JNI, no business logic. Default factories, validation, and computed
 * properties that adapt Wire millisecond fields into seconds-based Doubles
 * to match the cross-SDK public API surface.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.AudioFormat
import ai.runanywhere.proto.v1.TTSConfiguration
import ai.runanywhere.proto.v1.TTSOptions
import ai.runanywhere.proto.v1.TTSPhonemeTimestamp
import ai.runanywhere.proto.v1.TTSSpeakResult
import ai.runanywhere.proto.v1.TTSSynthesisMetadata
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.types.RATTSOptions
import com.runanywhere.sdk.public.types.RATTSOutput

// MARK: - TTSConfiguration

/**
 * Default TTS configuration: PCM at 22.05 kHz, neural voice on, SSML off.
 * Mirrors Swift `RATTSConfiguration.defaults(...)`.
 */
fun TTSConfiguration.Companion.defaults(
    modelId: String = "",
    voice: String = "default",
    languageCode: String = "en-US",
): TTSConfiguration =
    TTSConfiguration(
        model_id = modelId,
        voice = voice,
        language_code = languageCode,
        speaking_rate = 1.0f,
        pitch = 1.0f,
        volume = 1.0f,
        audio_format = AudioFormat.AUDIO_FORMAT_PCM,
        sample_rate = 22_050,
        enable_neural_voice = true,
        enable_ssml = false,
    )

/**
 * Validate this configuration. Throws [SDKException] on out-of-range values.
 * Mirrors Swift `RATTSConfiguration.validate()` — only validates non-zero
 * values so that proto3 defaults are not rejected.
 */
@Throws(SDKException::class)
fun TTSConfiguration.validate() {
    if (speaking_rate != 0f && (speaking_rate < 0.5f || speaking_rate > 2.0f)) {
        throw SDKException.invalidArgument(
            "Speaking rate must be in 0.5...2.0 (got $speaking_rate)",
        )
    }
    if (pitch != 0f && (pitch < 0.5f || pitch > 2.0f)) {
        throw SDKException.invalidArgument(
            "Pitch must be in 0.5...2.0 (got $pitch)",
        )
    }
    if (volume != 0f && (volume < 0.0f || volume > 1.0f)) {
        throw SDKException.invalidArgument(
            "Volume must be in 0.0...1.0 (got $volume)",
        )
    }
}

// MARK: - TTSOptions

/**
 * Default TTS runtime options. Mirrors Swift `RATTSOptions.defaults()`.
 */
fun TTSOptions.Companion.defaults(): RATTSOptions =
    RATTSOptions(
        language_code = "en-US",
        speaking_rate = 1.0f,
        pitch = 1.0f,
        volume = 1.0f,
        enable_ssml = false,
        audio_format = AudioFormat.AUDIO_FORMAT_PCM,
        sample_rate = 22_050,
    )

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
