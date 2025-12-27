//
//  VADOutput.swift
//  RunAnywhere SDK
//
//  Output model from Voice Activity Detection processing
//

import Foundation

/// Output from Voice Activity Detection processing
public struct VADOutput: ComponentOutput, Sendable {

    /// Whether speech is detected in the current frame
    public let isSpeechDetected: Bool

    /// Current audio energy level (RMS value)
    public let energyLevel: Float

    /// Timestamp of this detection
    public let timestamp: Date

    // MARK: - Initialization

    public init(
        isSpeechDetected: Bool,
        energyLevel: Float,
        timestamp: Date = Date()
    ) {
        self.isSpeechDetected = isSpeechDetected
        self.energyLevel = energyLevel
        self.timestamp = timestamp
    }
}

// MARK: - Convenience Extensions

extension VADOutput {

    /// Create output indicating speech detected
    public static func speechDetected(energyLevel: Float) -> VADOutput {
        VADOutput(isSpeechDetected: true, energyLevel: energyLevel)
    }

    /// Create output indicating silence
    public static func silence(energyLevel: Float) -> VADOutput {
        VADOutput(isSpeechDetected: false, energyLevel: energyLevel)
    }
}
