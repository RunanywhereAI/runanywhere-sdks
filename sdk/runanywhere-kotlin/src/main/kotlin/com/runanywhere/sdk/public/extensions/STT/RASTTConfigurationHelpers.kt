/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Ergonomic helpers for canonical STT proto types.
 *
 * defaults() / validate() live in generated/convenience/RAConvenience.kt,
 * emitted from the canonical IDL annotations. This file contains only
 * Kotlin-specific computed helpers.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.TranscriptionAlternative
import ai.runanywhere.proto.v1.TranscriptionMetadata
import ai.runanywhere.proto.v1.WordTimestamp
import com.runanywhere.sdk.public.types.RASTTOutput

// MARK: - STTOutput

/**
 * Convenience alias for the detected BCP-47 language code on the output
 * (`null` when the engine did not report one). Mirrors Swift
 * `RASTTOutput.detectedLanguageCode`.
 */
val RASTTOutput.detectedLanguageCode: String?
    get() = language

// MARK: - WordTimestamp

/**
 * Construct a [WordTimestamp] from seconds-based timing values, mirroring
 * Swift's `RAWordTimestamp(word:startTime:endTime:confidence:)`.
 */
fun WordTimestamp.Companion.create(
    word: String,
    startTime: Double,
    endTime: Double,
    confidence: Float,
): WordTimestamp =
    WordTimestamp(
        word = word,
        start_ms = (startTime * 1000.0).toLong(),
        end_ms = (endTime * 1000.0).toLong(),
        confidence = confidence,
    )

/** Start time in seconds. */
val WordTimestamp.startTime: Double
    get() = start_ms.toDouble() / 1000.0

/** End time in seconds. */
val WordTimestamp.endTime: Double
    get() = end_ms.toDouble() / 1000.0

/** Duration in seconds (clamped to >= 0). */
val WordTimestamp.duration: Double
    get() = (endTime - startTime).coerceAtLeast(0.0)

// MARK: - TranscriptionMetadata

/**
 * Computed real-time-factor (processing_time_ms / audio_length_ms).
 * Returns 0 when audio length is zero. Mirrors Swift
 * `RATranscriptionMetadata.realTimeFactorComputed`.
 */
val TranscriptionMetadata.realTimeFactorComputed: Double
    get() =
        if (audio_length_ms > 0) {
            processing_time_ms.toDouble() / audio_length_ms.toDouble()
        } else {
            0.0
        }

/** Processing time in seconds. */
val TranscriptionMetadata.processingTime: Double
    get() = processing_time_ms.toDouble() / 1000.0

/** Audio length in seconds. */
val TranscriptionMetadata.audioLength: Double
    get() = audio_length_ms.toDouble() / 1000.0

// MARK: - TranscriptionAlternative

/**
 * Construct a [TranscriptionAlternative] from text and confidence, mirroring
 * Swift's `RATranscriptionAlternative(text:confidence:)`.
 */
fun TranscriptionAlternative.Companion.create(
    text: String,
    confidence: Float,
): TranscriptionAlternative =
    TranscriptionAlternative(
        text = text,
        confidence = confidence,
    )
