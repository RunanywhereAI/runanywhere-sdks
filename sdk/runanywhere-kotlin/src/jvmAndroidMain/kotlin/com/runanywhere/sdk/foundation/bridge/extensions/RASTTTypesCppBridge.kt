/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * RASTTTypesCppBridge.kt
 *
 * C-bridge extensions on proto-generated RA* STT types.
 *
 * Mirrors Swift `Foundation/Bridge/Extensions/RASTTTypes+CppBridge.swift`.
 * Pure conversion / ergonomic helpers; no JNI.
 *
 * Companion sibling `RASTTConfigurationHelpers.kt` (in
 * `public.extensions.STT`) already covers `STTLanguage.bcp47Code`,
 * `STTLanguage.fromBcp47`, defaults factories, and validation. This file
 * adds the per-type accessors that Swift's `RASTTTypes+CppBridge.swift`
 * exposes (`STTOptions.languageString`, `STTPartialResult.transcript`).
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.STTConfiguration
import ai.runanywhere.proto.v1.STTLanguage
import ai.runanywhere.proto.v1.STTPartialResult
import com.runanywhere.sdk.public.types.RASTTOptions

// MARK: - RASTTConfiguration

/**
 * Returns the configuration's `model_id` or `null` when it's the proto3
 * default (empty string). Mirrors Swift `RASTTConfiguration.modelId`.
 */
val STTConfiguration.modelIdOrNull: String?
    get() = model_id.takeIf { it.isNotEmpty() }

// MARK: - RASTTOptions: language helpers

/**
 * Canonical short language string for the options' `language` enum
 * (e.g. "en", "es", "auto"). Mirrors Swift `RASTTOptions.languageString`.
 * Returns "en" for `UNSPECIFIED` / unknown to match Swift's fallback.
 */
val RASTTOptions.languageString: String
    get() =
        when (language) {
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
            STTLanguage.STT_LANGUAGE_UNSPECIFIED -> "en"
        }

/**
 * Parse a free-form language tag into the canonical `STTLanguage` enum.
 * Strips region suffixes ("en-US" → "en") and lowercases. Falls back to
 * `STT_LANGUAGE_EN` on unknown inputs to mirror Swift's default.
 *
 * Mirrors Swift `RASTTOptions.languageFromString(_:)`.
 */
fun sttLanguageFromString(raw: String): STTLanguage {
    val base = raw.substringBefore('-').lowercase()
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
        else -> STTLanguage.STT_LANGUAGE_EN
    }
}

// MARK: - RASTTPartialResult

/**
 * Alias for `text` on a partial transcription result. Mirrors Swift
 * `RASTTPartialResult.transcript`.
 */
val STTPartialResult.transcript: String
    get() = text
