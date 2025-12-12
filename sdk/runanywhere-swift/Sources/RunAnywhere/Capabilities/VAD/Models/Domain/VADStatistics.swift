//
//  VADStatistics.swift
//  RunAnywhere SDK
//
//  Statistics for VAD debugging and monitoring
//

import Foundation

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

    // MARK: - Initialization

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
}

// MARK: - Debug Description

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
