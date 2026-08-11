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
 * `public.extensions.STT`) already covers defaults factories and validation.
 * This file adds the per-type accessors that Swift's
 * `RASTTTypes+CppBridge.swift` exposes (`STTOptions.languageString`,
 * `STTPartialResult.transcript`).
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.STTConfiguration
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
 * BCP-47 language tag for the options, or "auto" when unset (null = engine
 * auto-detect). Mirrors Swift `RASTTOptions.languageString`.
 */
val RASTTOptions.languageString: String
    get() = language?.takeIf { it.isNotEmpty() } ?: "auto"

// MARK: - RASTTPartialResult

/**
 * Alias for `text` on a partial transcription result. Mirrors Swift
 * `RASTTPartialResult.transcript`.
 */
val STTPartialResult.transcript: String
    get() = text
