/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Ergonomic helpers for canonical VAD proto types.
 *
 * Mirrors Swift RAVADConfiguration+Helpers.swift exactly. Pure ergonomics —
 * no JNI, no business logic. Default factories, validation, and computed
 * properties that adapt Wire millisecond fields into seconds-based Doubles
 * to match the cross-SDK public API surface.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.SpeechActivityEvent
import ai.runanywhere.proto.v1.SpeechActivityKind
import ai.runanywhere.proto.v1.VADConfiguration
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.types.RAVADResult

// MARK: - VADConfiguration

/**
 * Default VAD configuration: 16 kHz, 100 ms frames, 0.015 energy threshold,
 * auto-calibration disabled. Mirrors Swift `RAVADConfiguration.defaults()`.
 */
fun VADConfiguration.Companion.defaults(): VADConfiguration =
    VADConfiguration(
        sample_rate = 16_000,
        frame_length_ms = 100,
        threshold = 0.015f,
        enable_auto_calibration = false,
    )

/**
 * Validate this configuration. Throws [SDKException] on out-of-range values.
 * Mirrors Swift `RAVADConfiguration.validate()`.
 */
@Throws(SDKException::class)
fun VADConfiguration.validate() {
    if (threshold < 0f || threshold > 1.0f) {
        throw SDKException.invalidArgument(
            "Energy threshold must be in 0...1.0 (got $threshold)",
        )
    }
    if (sample_rate <= 0 || sample_rate > 48_000) {
        throw SDKException.invalidArgument(
            "Sample rate must be in 1...48000 Hz (got $sample_rate)",
        )
    }
    if (frame_length_ms <= 0 || frame_length_ms > 1_000) {
        throw SDKException.invalidArgument(
            "Frame length must be in 1...1000 ms (got $frame_length_ms)",
        )
    }
}

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
