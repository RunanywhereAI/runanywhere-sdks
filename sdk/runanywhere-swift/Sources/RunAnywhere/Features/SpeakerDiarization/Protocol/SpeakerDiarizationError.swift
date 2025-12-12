//
//  SpeakerDiarizationError.swift
//  RunAnywhere SDK
//
//  Errors that can occur during Speaker Diarization operations
//

import Foundation

// MARK: - Speaker Diarization Error

/// Errors that can occur during speaker diarization operations
public enum SpeakerDiarizationError: Error, LocalizedError, Sendable {

    // MARK: - Initialization Errors

    /// No provider found for the requested model
    case noProviderFound(modelId: String?)

    /// Service failed to initialize
    case initializationFailed(underlying: Error)

    /// Model file not found at path
    case modelNotFound(path: String)

    // MARK: - Runtime Errors

    /// Service not initialized before use
    case notInitialized

    /// Diarization processing failed
    case processingFailed(reason: String)

    /// Invalid audio format
    case invalidAudioFormat(expected: String, received: String)

    /// Audio too short for diarization
    case audioTooShort(minimumSeconds: Double)

    /// No speakers detected in audio
    case noSpeakersDetected

    // MARK: - Configuration Errors

    /// Invalid configuration provided
    case invalidConfiguration(reason: String)

    /// Max speakers must be between 1 and 100
    case invalidMaxSpeakers(value: Int)

    /// Invalid threshold value
    case invalidThreshold(value: Float)

    // MARK: - Resource Errors

    /// Insufficient memory for model
    case insufficientMemory(required: Int64, available: Int64)

    /// Operation cancelled
    case cancelled

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .noProviderFound(let modelId):
            if let modelId = modelId {
                return "No speaker diarization provider found for model: \(modelId)"
            }
            return "No speaker diarization provider available"
        case .initializationFailed(let error):
            return "Speaker diarization initialization failed: \(error.localizedDescription)"
        case .modelNotFound(let path):
            return "Speaker diarization model not found at: \(path)"
        case .notInitialized:
            return "Speaker diarization service not initialized. Call initialize() first."
        case .processingFailed(let reason):
            return "Speaker diarization processing failed: \(reason)"
        case .invalidAudioFormat(let expected, let received):
            return "Invalid audio format. Expected \(expected), received \(received)"
        case .audioTooShort(let minimum):
            return "Audio too short. Minimum \(minimum) seconds required."
        case .noSpeakersDetected:
            return "No speakers detected in the audio"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        case .invalidMaxSpeakers(let value):
            return "Invalid max speakers value: \(value). Must be between 1 and 100."
        case .invalidThreshold(let value):
            return "Invalid threshold value: \(value). Must be between 0 and 1."
        case .insufficientMemory(let required, let available):
            return "Insufficient memory. Required: \(required) bytes, Available: \(available) bytes"
        case .cancelled:
            return "Speaker diarization operation was cancelled"
        }
    }
}
