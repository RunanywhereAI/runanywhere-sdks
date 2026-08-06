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
import com.runanywhere.sdk.public.types.RATTSOptions
import com.runanywhere.sdk.public.types.RATTSOutput

// `TTSConfiguration` (idl/tts_options.proto) left the v2 contract entirely --
// TTSOptions now owns every synthesis knob -- so the `modelIdOrNull` alias
// built on it has no wire type to attach to any more and is dropped, per
// Swift's `RATTSTypes+CppBridge.swift`.

// MARK: - RATTSOptions: aliases

/**
 * Alias for `speed` — Swift's `RATTSOptions.rate`.
 * Provided as a read-only computed property since Wire-generated types are
 * immutable; use `.copy(speed = ...)` to modify.
 */
val RATTSOptions.rate: Float
    get() = speed

/**
 * Alias for `language_code` — Swift's `RATTSOptions.language`.
 */
val RATTSOptions.language: String
    get() = language_code

// `enable_ssml`/`useSSML` is deleted outright (idl/tts_options.proto), zero
// live callers of either -- dropped rather than rehomed, per Swift.

// MARK: - RATTSOutput

/**
 * Alias for `audio_format` — Swift's `RATTSOutput.format`.
 */
val RATTSOutput.format: AudioFormat
    get() = audio_format
