//
//  RAVADConfiguration+Helpers.swift
//  RunAnywhere SDK
//
//  Ergonomic helpers for canonical VAD proto types.
//

import Foundation

// MARK: - RAVADConfiguration

extension RAVADConfiguration {
    public static func defaults() -> RAVADConfiguration {
        var c = RAVADConfiguration()
        c.sampleRate = 16_000
        c.frameLengthMs = 100
        c.threshold = 0.015
        c.enableAutoCalibration = false
        return c
    }

    public func validate() throws {
        guard threshold >= 0 && threshold <= 1.0 else {
            throw SDKException.validationFailed(
                "Energy threshold must be in 0...1.0 (got \(threshold))"
            )
        }
        guard sampleRate > 0 && sampleRate <= 48_000 else {
            throw SDKException.validationFailed(
                "Sample rate must be in 1...48000 Hz (got \(sampleRate))"
            )
        }
        guard frameLengthMs > 0 && frameLengthMs <= 1_000 else {
            throw SDKException.validationFailed(
                "Frame length must be in 1...1000 ms (got \(frameLengthMs))"
            )
        }
    }

    public var frameLengthSeconds: Float { Float(frameLengthMs) / 1000.0 }
}

// MARK: - RAVADResult

extension RAVADResult {
    public var duration: TimeInterval { TimeInterval(durationMs) / 1000.0 }
}

// MARK: - RASpeechActivityEvent

extension RASpeechActivityEvent {
    public var timestamp: Date {
        Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000.0)
    }

    public var duration: TimeInterval { TimeInterval(durationMs) / 1000.0 }
}

// MARK: - RASpeechActivityKind

extension RASpeechActivityKind {
    public var isTransition: Bool {
        self == .speechStarted || self == .speechEnded
    }
}
