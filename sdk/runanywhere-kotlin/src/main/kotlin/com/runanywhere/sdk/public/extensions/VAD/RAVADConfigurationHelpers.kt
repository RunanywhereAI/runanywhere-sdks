/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Ergonomic helpers for canonical VAD proto types.
 *
 * defaults() / validate() live in generated/convenience/RAConvenience.kt,
 * emitted from the canonical IDL annotations. This file contains only
 * Kotlin-specific computed helpers.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.SpeechActivityEvent
import ai.runanywhere.proto.v1.SpeechActivityKind
import ai.runanywhere.proto.v1.VADConfiguration
import com.runanywhere.sdk.public.types.RAVADResult

// MARK: - VADConfiguration

/** Frame length expressed in seconds. */
val VADConfiguration.frameLengthSeconds: Float
    get() = frame_length_ms.toFloat() / 1000f

// MARK: - VADResult

/** Frame duration in seconds. */
val RAVADResult.duration: Double
    get() = duration_ms.toDouble() / 1000.0

// MARK: - SpeechActivityEvent

/** Wall-clock timestamp in milliseconds since the Unix epoch. */
val SpeechActivityEvent.timestampEpochMs: Long
    get() = timestamp_ms

/** Event-carried duration in seconds (set on SPEECH_ENDED). */
val SpeechActivityEvent.duration: Double
    get() = duration_ms.toDouble() / 1000.0

// MARK: - SpeechActivityKind

/**
 * True for the narrow start/end transitions; false for ONGOING / UNSPECIFIED.
 * Mirrors Swift `RASpeechActivityKind.isTransition`.
 */
val SpeechActivityKind.isTransition: Boolean
    get() =
        this == SpeechActivityKind.SPEECH_ACTIVITY_KIND_SPEECH_STARTED ||
            this == SpeechActivityKind.SPEECH_ACTIVITY_KIND_SPEECH_ENDED
