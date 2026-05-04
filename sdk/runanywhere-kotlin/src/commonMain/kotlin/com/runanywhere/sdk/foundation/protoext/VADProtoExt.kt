/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Extension helpers for the proto-canonical VAD types
 * (ai.runanywhere.proto.v1.{VADConfiguration, VADStatistics, VADResult,
 *  VADOptions, SpeechActivityEvent}).
 */

package com.runanywhere.sdk.foundation.protoext

import ai.runanywhere.proto.v1.VADConfiguration
import ai.runanywhere.proto.v1.VADStatistics

const val VAD_DEFAULT_SAMPLE_RATE: Int = 16000
const val VAD_DEFAULT_FRAME_LENGTH_MS: Int = 100
const val VAD_DEFAULT_THRESHOLD: Float = 0.015f

/**
 * Validate this VADConfiguration against canonical ranges.
 *
 * @throws IllegalArgumentException if validation fails
 */
fun VADConfiguration.validate() {
    require(threshold == 0f || threshold in 0f..1f) {
        "Energy threshold must be between 0 and 1.0 (got $threshold)"
    }
    require(sample_rate == 0 || sample_rate in 1..48000) {
        "Sample rate must be between 1 and 48000 Hz (got $sample_rate)"
    }
    require(frame_length_ms == 0 || frame_length_ms in 1..1000) {
        "Frame length must be between 1 and 1000 milliseconds (got $frame_length_ms)"
    }
}

/** Effective sample rate, falling back to canonical default (16 kHz). */
val VADConfiguration.effectiveSampleRate: Int
    get() = if (sample_rate > 0) sample_rate else VAD_DEFAULT_SAMPLE_RATE

/** Effective frame length in ms, falling back to canonical default (100 ms). */
val VADConfiguration.effectiveFrameLengthMs: Int
    get() = if (frame_length_ms > 0) frame_length_ms else VAD_DEFAULT_FRAME_LENGTH_MS

/** Effective energy threshold, falling back to canonical default (0.015). */
val VADConfiguration.effectiveThreshold: Float
    get() = if (threshold > 0f) threshold else VAD_DEFAULT_THRESHOLD

/**
 * Format VADStatistics as a multi-line debug string.
 */
fun VADStatistics.format(): String =
    """
    VADStatistics:
      Current: $current_energy
      Threshold: $current_threshold
      Ambient: $ambient_level
      Recent Avg: $recent_avg
      Recent Max: $recent_max
    """.trimIndent()
