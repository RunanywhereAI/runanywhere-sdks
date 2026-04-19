//
//  VADTypes.swift
//  RunAnywhere SDK
//
//  Public types for Voice Activity Detection.
//  These are thin wrappers over C++ types in rac_vad_types.h
//

import CRACommons
import Foundation

// MARK: - VAD Configuration

/// Configuration for Voice Activity Detection operations
public struct VADConfiguration: ComponentConfiguration, Sendable {

    // MARK: - ComponentConfiguration

    /// Component type
    public var componentType: SDKComponent { .vad }

    /// Model ID (not used for VAD)
    public var modelId: String? { nil }

    /// Preferred framework (uses default extension implementation)
    public var preferredFramework: InferenceFramework? { nil }

    // MARK: - Configuration Properties

    /// Energy threshold for voice detection (0.0 to 1.0)
    /// Recommended range: 0.01-0.05
    public let energyThreshold: Float

    /// Sample rate in Hz (default: 16000)
    public let sampleRate: Int

    /// Frame length in seconds (default: 0.1 = 100ms)
    public let frameLength: Float

    /// Enable automatic calibration
    public let enableAutoCalibration: Bool

    /// Calibration multiplier (threshold = ambient noise * multiplier)
    /// Range: 1.5 to 5.0
    public let calibrationMultiplier: Float

    // MARK: - Initialization

    public init(
        energyThreshold: Float = 0.015,
        sampleRate: Int = Int(RAC_VAD_DEFAULT_SAMPLE_RATE),
        frameLength: Float = 0.1,
        enableAutoCalibration: Bool = false,
        calibrationMultiplier: Float = 2.0
    ) {
        self.energyThreshold = energyThreshold
        self.sampleRate = sampleRate
        self.frameLength = frameLength
        self.enableAutoCalibration = enableAutoCalibration
        self.calibrationMultiplier = calibrationMultiplier
    }

    // MARK: - Validation

    public func validate() throws {
        // Validate threshold range
        guard energyThreshold >= 0 && energyThreshold <= 1.0 else {
            throw SDKError.vad(
                .invalidConfiguration,
                "Energy threshold must be between 0 and 1.0. Recommended range: 0.01-0.05"
            )
        }

        // Warn if threshold is too low
        if energyThreshold < 0.002 {
            throw SDKError.vad(
                .invalidConfiguration,
                "Energy threshold \(energyThreshold) is very low and may cause false positives. Recommended minimum: 0.002"
            )
        }

        // Warn if threshold is too high
        if energyThreshold > 0.1 {
            throw SDKError.vad(
                .invalidConfiguration,
                "Energy threshold \(energyThreshold) is very high and may miss speech. Recommended maximum: 0.1"
            )
        }

        // Validate sample rate
        guard sampleRate > 0 && sampleRate <= 48000 else {
            throw SDKError.vad(
                .invalidConfiguration,
                "Sample rate must be between 1 and 48000 Hz"
            )
        }

        // Validate frame length
        guard frameLength > 0 && frameLength <= 1.0 else {
            throw SDKError.vad(
                .invalidConfiguration,
                "Frame length must be between 0 and 1 second"
            )
        }

        // Validate calibration multiplier
        guard calibrationMultiplier >= 1.5 && calibrationMultiplier <= 5.0 else {
            throw SDKError.vad(
                .invalidConfiguration,
                "Calibration multiplier must be between 1.5 and 5.0"
            )
        }
    }
}

// MARK: - VADConfiguration Builder

extension VADConfiguration {

    /// Create configuration with builder pattern
    public static func builder() -> Builder {
        Builder()
    }

    public class Builder {
        private var energyThreshold: Float = 0.015
        private var sampleRate = Int(RAC_VAD_DEFAULT_SAMPLE_RATE)
        private var frameLength: Float = 0.1
        private var enableAutoCalibration: Bool = false
        private var calibrationMultiplier: Float = 2.0

        public init() {}

        public func energyThreshold(_ threshold: Float) -> Builder {
            self.energyThreshold = threshold
            return self
        }

        public func sampleRate(_ rate: Int) -> Builder {
            self.sampleRate = rate
            return self
        }

        public func frameLength(_ length: Float) -> Builder {
            self.frameLength = length
            return self
        }

        public func enableAutoCalibration(_ enabled: Bool) -> Builder {
            self.enableAutoCalibration = enabled
            return self
        }

        public func calibrationMultiplier(_ multiplier: Float) -> Builder {
            self.calibrationMultiplier = multiplier
            return self
        }

        public func build() -> VADConfiguration {
            VADConfiguration(
                energyThreshold: energyThreshold,
                sampleRate: sampleRate,
                frameLength: frameLength,
                enableAutoCalibration: enableAutoCalibration,
                calibrationMultiplier: calibrationMultiplier
            )
        }
    }
}

// MARK: - VAD Statistics

/// Statistics for VAD debugging and monitoring
public struct VADStatistics: Sendable {

    /// Current energy level
    public let current: Float

    /// Energy threshold being used
    public let threshold: Float

    /// Ambient noise level (from calibration)
    public let ambient: Float

    /// Recent average energy level
    public let recentAvg: Float

    /// Recent maximum energy level
    public let recentMax: Float

    public init(
        current: Float,
        threshold: Float,
        ambient: Float,
        recentAvg: Float,
        recentMax: Float
    ) {
        self.current = current
        self.threshold = threshold
        self.ambient = ambient
        self.recentAvg = recentAvg
        self.recentMax = recentMax
    }

    // MARK: - C++ Bridge (rac_energy_vad_stats_t)

    /// Initialize from C++ rac_energy_vad_stats_t
    public init(from cStats: rac_energy_vad_stats_t) {
        self.init(
            current: cStats.current,
            threshold: cStats.threshold,
            ambient: cStats.ambient,
            recentAvg: cStats.recent_avg,
            recentMax: cStats.recent_max
        )
    }
}

extension VADStatistics: CustomStringConvertible {
    public var description: String {
        """
        VADStatistics:
          Current: \(String(format: "%.6f", current))
          Threshold: \(String(format: "%.6f", threshold))
          Ambient: \(String(format: "%.6f", ambient))
          Recent Avg: \(String(format: "%.6f", recentAvg))
          Recent Max: \(String(format: "%.6f", recentMax))
        """
    }
}

// MARK: - Speech Activity Event

/// Events representing speech activity state changes
public enum SpeechActivityEvent: String, Sendable {
    /// Speech has started
    case started

    /// Speech has ended
    case ended
}
