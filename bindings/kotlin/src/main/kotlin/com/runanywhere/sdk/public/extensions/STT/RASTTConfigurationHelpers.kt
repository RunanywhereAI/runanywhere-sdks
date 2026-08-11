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

// `TranscriptionMetadata.audio_length_ms` is deleted outright
// (idl/stt_options.proto) with no replacement field; `realTimeFactorComputed`
// and `audioLength` were pure derivations of it with no independent wire
// value, so both are dropped rather than rehomed, matching Swift's
// `RASTTConfiguration+Helpers.swift`, which carries neither any more.
// `processingTime` (processing_time_ms / 1000.0) still stands on its own
// surviving field.

/** Processing time in seconds. */
val TranscriptionMetadata.processingTime: Double
    get() = processing_time_ms.toDouble() / 1000.0

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
