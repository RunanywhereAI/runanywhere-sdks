//
//  VADError.swift
//  RunAnywhere SDK
//
//  Errors that can occur during Voice Activity Detection operations
//

import Foundation

/// Errors that can occur during Voice Activity Detection operations
public enum VADError: Error, LocalizedError, Sendable {

    // MARK: - Initialization Errors

    /// Service not initialized before use
    case notInitialized

    /// Service failed to initialize
    case initializationFailed(reason: String)

    /// Invalid configuration provided
    case invalidConfiguration(reason: String)

    // MARK: - Runtime Errors

    /// VAD service not available
    case serviceNotAvailable

    /// Processing failed
    case processingFailed(reason: String)

    /// Invalid audio format
    case invalidAudioFormat(expected: String, received: String)

    /// Audio buffer is empty
    case emptyAudioBuffer

    /// Invalid input provided
    case invalidInput(reason: String)

    // MARK: - Calibration Errors

    /// Calibration failed
    case calibrationFailed(reason: String)

    /// Calibration timeout
    case calibrationTimeout

    // MARK: - Resource Errors

    /// Operation cancelled
    case cancelled

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "VAD service not initialized. Call initialize() first."
        case .initializationFailed(let reason):
            return "VAD initialization failed: \(reason)"
        case .invalidConfiguration(let reason):
            return "Invalid VAD configuration: \(reason)"
        case .serviceNotAvailable:
            return "VAD service not available"
        case .processingFailed(let reason):
            return "VAD processing failed: \(reason)"
        case .invalidAudioFormat(let expected, let received):
            return "Invalid audio format. Expected \(expected), received \(received)"
        case .emptyAudioBuffer:
            return "Cannot process empty audio buffer"
        case .invalidInput(let reason):
            return "Invalid VAD input: \(reason)"
        case .calibrationFailed(let reason):
            return "VAD calibration failed: \(reason)"
        case .calibrationTimeout:
            return "VAD calibration timed out"
        case .cancelled:
            return "VAD operation was cancelled"
        }
    }
}
