/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Extension helpers for the proto-canonical STT types
 * (ai.runanywhere.proto.v1.{STTConfiguration, STTOptions, STTOutput, STTLanguage,
 *  TranscriptionMetadata}).
 *
 * The Wire-generated proto types are wire-canonical but lack the helper
 * methods, factories, and computed properties that the legacy hand-rolled
 * Kotlin types provided. These extensions restore that ergonomics while
 * leaving the generated `.kt` bindings untouched.
 */

package com.runanywhere.sdk.foundation.protoext

import ai.runanywhere.proto.v1.STTConfiguration
import ai.runanywhere.proto.v1.STTLanguage
import ai.runanywhere.proto.v1.STTOptions
import ai.runanywhere.proto.v1.STTOutput
import ai.runanywhere.proto.v1.TranscriptionMetadata

// ============================================================================
// STTConfiguration helpers
// ============================================================================

const val STT_DEFAULT_SAMPLE_RATE: Int = 16000

/**
 * Validate this STTConfiguration.
 *
 * @throws IllegalArgumentException if validation fails
 */
fun STTConfiguration.validate() {
    val sr = sample_rate
    require(sr == 0 || sr in 1..48000) {
        "Sample rate must be between 1 and 48000 Hz (got $sr)"
    }
    // model_id may be empty string when proto default; treat blank as "unset"
}

/**
 * Effective sample rate — falls back to the canonical default (16 kHz)
 * when the proto value is the proto3 zero default.
 */
val STTConfiguration.effectiveSampleRate: Int
    get() = if (sample_rate > 0) sample_rate else STT_DEFAULT_SAMPLE_RATE

/**
 * Whether a model id has been configured (non-blank).
 */
val STTConfiguration.hasModelId: Boolean
    get() = model_id.isNotBlank()

// ============================================================================
// STTOptions helpers
// ============================================================================

/**
 * Default STTOptions instance for a given language code (BCP-47 base).
 *
 * @param language Language code (default "en")
 */
fun sttOptionsDefault(language: STTLanguage = STTLanguage.STT_LANGUAGE_EN): STTOptions =
    STTOptions(language = language, enable_word_timestamps = true, enable_punctuation = true)

// ============================================================================
// STTLanguage helpers
// ============================================================================

/**
 * Convert a proto STTLanguage to a BCP-47 base language string.
 * Returns "en" for unspecified / auto.
 */
val STTLanguage.bcp47: String
    get() =
        when (this) {
            STTLanguage.STT_LANGUAGE_UNSPECIFIED -> "en"
            STTLanguage.STT_LANGUAGE_AUTO -> "en"
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

/**
 * Parse a BCP-47 base language string into a proto STTLanguage.
 * Falls back to STT_LANGUAGE_UNSPECIFIED for unrecognized values.
 */
fun sttLanguageFromBcp47(code: String): STTLanguage {
    val base = code.substringBefore('-').lowercase()
    return when (base) {
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
        "auto" -> STTLanguage.STT_LANGUAGE_AUTO
        else -> STTLanguage.STT_LANGUAGE_UNSPECIFIED
    }
}

// ============================================================================
// TranscriptionMetadata helpers
// ============================================================================

/**
 * Computed real-time factor: processing_time_ms / audio_length_ms.
 * Returns 0.0 if audio length is zero. Prefer this over the producer-set
 * `real_time_factor` field when consumers want a guaranteed-fresh value.
 */
val TranscriptionMetadata.computedRealTimeFactor: Double
    get() = if (audio_length_ms > 0) processing_time_ms.toDouble() / audio_length_ms.toDouble() else 0.0

// ============================================================================
// STTOutput helpers
// ============================================================================

/**
 * Whether the output has word-level timestamps.
 */
val STTOutput.hasWordTimestamps: Boolean
    get() = words.isNotEmpty()

/**
 * Whether the output has alternative transcriptions.
 */
val STTOutput.hasAlternatives: Boolean
    get() = alternatives.isNotEmpty()
