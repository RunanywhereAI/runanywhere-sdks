/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * RATTSTypesCppBridge.kt
 *
 * C-bridge extensions on proto-generated RA* TTS types.
 *
 * Mirrors Swift `Foundation/Bridge/Extensions/RATTSTypes+CppBridge.swift`.
 * Pure ergonomic accessors / aliases; no JNI.
 *
 * Canonical defaults live in generated/convenience/RAConvenience.kt. The
 * public TTS helpers provide timestamp accessors; this file adds the
 * Swift-style read-only aliases that round out the `RATTSOptions` /
 * `RATTSOutput` public surface.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.AudioFormat
import ai.runanywhere.proto.v1.TTSConfiguration
import com.runanywhere.sdk.public.types.RATTSOptions
import com.runanywhere.sdk.public.types.RATTSOutput

// MARK: - RATTSConfiguration

/**
 * Returns the configuration's `model_id` or `null` when it's the proto3
 * default (empty string). Mirrors Swift `RATTSConfiguration.modelId`.
 */
val TTSConfiguration.modelIdOrNull: String?
    get() = model_id.takeIf { it.isNotEmpty() }

// MARK: - RATTSOptions: aliases

/**
 * Alias for `speaking_rate` — Swift's `RATTSOptions.rate`.
 * Provided as a read-only computed property since Wire-generated types are
 * immutable; use `.copy(speaking_rate = ...)` to modify.
 */
val RATTSOptions.rate: Float
    get() = speaking_rate

/**
 * Alias for `language_code` — Swift's `RATTSOptions.language`.
 */
val RATTSOptions.language: String
    get() = language_code

/**
 * Alias for `enable_ssml` — Swift's `RATTSOptions.useSSML`.
 */
val RATTSOptions.useSSML: Boolean
    get() = enable_ssml

// MARK: - RATTSOutput

/**
 * Alias for `audio_format` — Swift's `RATTSOutput.format`.
 */
val RATTSOutput.format: AudioFormat
    get() = audio_format
