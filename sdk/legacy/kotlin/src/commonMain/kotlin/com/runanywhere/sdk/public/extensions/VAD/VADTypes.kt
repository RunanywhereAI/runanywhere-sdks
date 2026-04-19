/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public types for Voice Activity Detection.
 * These are thin wrappers over C++ types in rac_vad_types.h
 *
 * Mirrors Swift VADTypes.swift exactly.
 */

package com.runanywhere.sdk.public.extensions.VAD

import com.runanywhere.sdk.core.types.ComponentConfiguration
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.core.types.SDKComponent
import com.runanywhere.sdk.foundation.errors.SDKError
import kotlinx.serialization.Serializable

// MARK: - VAD Configuration

/**
 * Configuration for Voice Activity Detection operations.
 * Mirrors Swift VADConfiguration exactly.
 */
@Serializable
data class VADConfiguration(
    /** Energy threshold for voice detection (0.0 to 1.0). Recommended range: 0.01-0.05 */
    val energyThreshold: Float = 0.015f,
    /** Sample rate in Hz (default: 16000) */
    val sampleRate: Int = DEFAULT_SAMPLE_RATE,
    /** Frame length in seconds (default: 0.1 = 100ms) */
    val frameLength: Float = 0.1f,
    /** Enable automatic calibration */
    val enableAutoCalibration: Boolean = false,
    /** Calibration multiplier (threshold = ambient noise * multiplier). Range: 1.5 to 5.0 */
    val calibrationMultiplier: Float = 2.0f,
) : ComponentConfiguration {
    override val modelId: String? get() = null
    override val preferredFramework: InferenceFramework? get() = null

    val componentType: SDKComponent get() = SDKComponent.VAD

    /**
     * Validate the configuration.
     * @throws SDKError if validation fails
     */
    fun validate() {
        // Validate threshold range
        require(energyThreshold in 0f..1f) {
            throw SDKError.vad("Energy threshold must be between 0 and 1.0. Recommended range: 0.01-0.05")
        }

        // Warn if threshold is too low
        if (energyThreshold < 0.002f) {
            throw SDKError.vad("Energy threshold $energyThreshold is very low and may cause false positives. Recommended minimum: 0.002")
        }

        // Warn if threshold is too high
        if (energyThreshold > 0.1f) {
            throw SDKError.vad("Energy threshold $energyThreshold is very high and may miss speech. Recommended maximum: 0.1")
        }

        // Validate sample rate
        require(sampleRate in 1..48000) {
            throw SDKError.vad("Sample rate must be between 1 and 48000 Hz")
        }

        // Validate frame length
        require(frameLength in 0f..1f) {
            throw SDKError.vad("Frame length must be between 0 and 1 second")
        }

        // Validate calibration multiplier
        require(calibrationMultiplier in 1.5f..5.0f) {
            throw SDKError.vad("Calibration multiplier must be between 1.5 and 5.0")
        }
    }

    /**
     * Builder pattern for VADConfiguration.
     */
    class Builder {
        private var energyThreshold: Float = 0.015f
        private var sampleRate: Int = DEFAULT_SAMPLE_RATE
        private var frameLength: Float = 0.1f
        private var enableAutoCalibration: Boolean = false
        private var calibrationMultiplier: Float = 2.0f

        fun energyThreshold(threshold: Float) = apply { energyThreshold = threshold }

        fun sampleRate(rate: Int) = apply { sampleRate = rate }

        fun frameLength(length: Float) = apply { frameLength = length }

        fun enableAutoCalibration(enabled: Boolean) = apply { enableAutoCalibration = enabled }

        fun calibrationMultiplier(multiplier: Float) = apply { calibrationMultiplier = multiplier }

        fun build() =
            VADConfiguration(
                energyThreshold = energyThreshold,
                sampleRate = sampleRate,
                frameLength = frameLength,
                enableAutoCalibration = enableAutoCalibration,
                calibrationMultiplier = calibrationMultiplier,
            )
    }

    companion object {
        const val DEFAULT_SAMPLE_RATE = 16000

        fun builder() = Builder()
    }
}

// MARK: - VAD Statistics

/**
 * Statistics for VAD debugging and monitoring.
 * Mirrors Swift VADStatistics exactly.
 */
@Serializable
data class VADStatistics(
    /** Current energy level */
    val current: Float,
    /** Energy threshold being used */
    val threshold: Float,
    /** Ambient noise level (from calibration) */
    val ambient: Float,
    /** Recent average energy level */
    val recentAvg: Float,
    /** Recent maximum energy level */
    val recentMax: Float,
) {
    override fun toString(): String =
        """
        VADStatistics:
          Current: ${String.format("%.6f", current)}
          Threshold: ${String.format("%.6f", threshold)}
          Ambient: ${String.format("%.6f", ambient)}
          Recent Avg: ${String.format("%.6f", recentAvg)}
          Recent Max: ${String.format("%.6f", recentMax)}
        """.trimIndent()
}

// MARK: - VAD Result

/**
 * Result from VAD processing.
 */
@Serializable
data class VADResult(
    /** Whether speech was detected */
    val isSpeech: Boolean,
    /** Confidence level (0.0 to 1.0) */
    val confidence: Float,
    /** Energy level of the audio */
    val energyLevel: Float,
    /** Statistics for debugging */
    val statistics: VADStatistics? = null,
    /** Timestamp */
    val timestamp: Long = System.currentTimeMillis(),
)

// MARK: - Speech Activity Event

/**
 * Events representing speech activity state changes.
 * Mirrors Swift SpeechActivityEvent exactly.
 */
enum class SpeechActivityEvent(
    val value: String,
) {
    /** Speech has started */
    STARTED("started"),

    /** Speech has ended */
    ENDED("ended"),
}
