//
//  VADConstants.swift
//  RunAnywhere SDK
//
//  Constants for Voice Activity Detection capability.
//  Centralizes hardcoded values with documentation.
//

import Foundation

// MARK: - VAD Constants

/// Constants for Voice Activity Detection capability.
///
/// These values are derived from audio processing best practices:
/// - VAD typically processes 16kHz audio for speech detection
/// - Energy-based VAD uses calibrated thresholds
/// - Frame lengths balance latency vs accuracy
public enum VADConstants {

    // MARK: - Audio Format

    /// Standard sample rate for VAD processing (16kHz).
    ///
    /// VAD algorithms are typically optimized for 16kHz audio,
    /// which provides sufficient frequency resolution for speech
    /// while minimizing computational overhead.
    public static let defaultSampleRate: Int = 16000

    /// Maximum supported sample rate (48kHz).
    ///
    /// Audio above this rate is typically downsampled before processing.
    public static let maxSampleRate: Int = 48000

    /// Minimum supported sample rate (8kHz).
    ///
    /// Audio below this rate may produce unreliable VAD results.
    public static let minSampleRate: Int = 8000

    // MARK: - Energy Thresholds

    /// Default energy threshold for speech detection.
    ///
    /// Audio frames with energy above this threshold are considered
    /// to contain speech. This value works well for typical environments.
    /// Use auto-calibration for noisy environments.
    public static let defaultEnergyThreshold: Float = 0.015

    /// Minimum energy threshold.
    ///
    /// Lower values increase sensitivity (more false positives).
    public static let minEnergyThreshold: Float = 0.001

    /// Maximum energy threshold.
    ///
    /// Higher values decrease sensitivity (more false negatives).
    public static let maxEnergyThreshold: Float = 0.5

    // MARK: - Frame Processing

    /// Default frame length in seconds.
    ///
    /// Audio is processed in frames of this duration.
    /// Shorter frames = lower latency, longer frames = more stable detection.
    public static let defaultFrameLength: Float = 0.1

    /// Minimum frame length in seconds.
    public static let minFrameLength: Float = 0.02

    /// Maximum frame length in seconds.
    public static let maxFrameLength: Float = 0.5

    // MARK: - Calibration

    /// Default multiplier for auto-calibration.
    ///
    /// The calibrated threshold = measured noise floor × this multiplier.
    /// Higher values reduce false positives in noisy environments.
    public static let defaultCalibrationMultiplier: Float = 2.0

    /// Minimum calibration multiplier.
    public static let minCalibrationMultiplier: Float = 1.2

    /// Maximum calibration multiplier.
    public static let maxCalibrationMultiplier: Float = 5.0

    // MARK: - Speech Detection

    /// Minimum speech duration to trigger detection (milliseconds).
    ///
    /// Speech segments shorter than this are ignored to reduce false positives.
    public static let minSpeechDurationMs: Int = 100

    /// Minimum silence duration to end speech segment (milliseconds).
    ///
    /// After speech is detected, this much silence ends the segment.
    public static let minSilenceDurationMs: Int = 300
}
