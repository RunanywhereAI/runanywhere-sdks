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

import ai.runanywhere.proto.v1.STTLanguage
import ai.runanywhere.proto.v1.TranscriptionAlternative
import ai.runanywhere.proto.v1.TranscriptionMetadata
import ai.runanywhere.proto.v1.WordTimestamp
import com.runanywhere.sdk.public.types.RASTTOutput

// MARK: - STTLanguage

/**
 * Map a BCP-47 language string (e.g. "en-US", "zh-Hans") to the canonical enum.
 */
fun STTLanguage.Companion.fromBcp47(raw: String): STTLanguage {
    val base = raw.split('-').firstOrNull()?.lowercase() ?: raw.lowercase()
    return when (base) {
        "auto" -> STTLanguage.STT_LANGUAGE_AUTO
        "en" -> STTLanguage.STT_LANGUAGE_EN
        "es" -> STTLanguage.STT_LANGUAGE_ES
        "fr" -> STTLanguage.STT_LANGUAGE_FR
        "de" -> STTLanguage.STT_LANGUAGE_DE
        "zh" -> STTLanguage.STT_LANGUAGE_ZH
        "ja" -> STTLanguage.STT_LANGUAGE_JA
        "ko" -> STTLanguage.STT_LANGUAGE_KO
        "it" -> STTLanguage.STT_LANGUAGE_IT
        "pt" -> STTLanguage.STT_LANGUAGE_PT
        "ar" -> STTLanguage.STT_LANGUAGE_AR
        "ru" -> STTLanguage.STT_LANGUAGE_RU
        "hi" -> STTLanguage.STT_LANGUAGE_HI
        else -> STTLanguage.STT_LANGUAGE_UNSPECIFIED
    }
}

val STTLanguage.bcp47Code: String
    get() =
        when (this) {
            STTLanguage.STT_LANGUAGE_UNSPECIFIED -> ""
            STTLanguage.STT_LANGUAGE_AUTO -> "auto"
            STTLanguage.STT_LANGUAGE_EN -> "en"
            STTLanguage.STT_LANGUAGE_ES -> "es"
            STTLanguage.STT_LANGUAGE_FR -> "fr"
            STTLanguage.STT_LANGUAGE_DE -> "de"
            STTLanguage.STT_LANGUAGE_ZH -> "zh"
            STTLanguage.STT_LANGUAGE_JA -> "ja"
            STTLanguage.STT_LANGUAGE_KO -> "ko"
            STTLanguage.STT_LANGUAGE_IT -> "it"
            STTLanguage.STT_LANGUAGE_PT -> "pt"
            STTLanguage.STT_LANGUAGE_AR -> "ar"
            STTLanguage.STT_LANGUAGE_RU -> "ru"
            STTLanguage.STT_LANGUAGE_HI -> "hi"
        }

// MARK: - STTOutput

/**
 * Convenience alias for the detected language enum on the output.
 * Mirrors Swift `RASTTOutput.detectedLanguageCode`.
 */
val RASTTOutput.detectedLanguageCode: STTLanguage
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
