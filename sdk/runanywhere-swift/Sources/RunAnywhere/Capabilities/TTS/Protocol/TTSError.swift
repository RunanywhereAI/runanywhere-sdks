//
//  TTSError.swift
//  RunAnywhere SDK
//
//  Typed errors for Text-to-Speech operations
//

import Foundation

/// Errors that can occur during Text-to-Speech operations
public enum TTSError: Error, LocalizedError, Sendable {

    // MARK: - Initialization Errors

    /// Service not initialized before use
    case notInitialized

    /// Service failed to initialize
    case initializationFailed(underlying: Error)

    /// No provider found for the requested voice/model
    case noProviderFound(voiceId: String)

    /// Model/voice file not found at path
    case modelNotFound(path: String)

    // MARK: - Configuration Errors

    /// Invalid configuration provided
    case invalidConfiguration(reason: String)

    /// Invalid speaking rate (must be 0.5-2.0)
    case invalidSpeakingRate(value: Float)

    /// Invalid pitch (must be 0.5-2.0)
    case invalidPitch(value: Float)

    /// Invalid volume (must be 0.0-1.0)
    case invalidVolume(value: Float)

    // MARK: - Input Errors

    /// Empty text provided for synthesis
    case emptyText

    /// Text too long for synthesis
    case textTooLong(maxCharacters: Int, received: Int)

    /// Invalid SSML markup
    case invalidSSML(reason: String)

    // MARK: - Runtime Errors

    /// Synthesis failed
    case synthesisFailed(reason: String)

    /// Voice not available
    case voiceNotAvailable(voiceId: String)

    /// Language not supported
    case languageNotSupported(language: String)

    /// Audio format not supported
    case audioFormatNotSupported(format: String)

    // MARK: - Resource Errors

    /// Insufficient memory for synthesis
    case insufficientMemory(required: Int64, available: Int64)

    /// Operation cancelled
    case cancelled

    /// Service is busy with another operation
    case busy

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "TTS service not initialized. Call initialize() first."
        case .initializationFailed(let error):
            return "TTS initialization failed: \(error.localizedDescription)"
        case .noProviderFound(let voiceId):
            return "No TTS provider found for voice: \(voiceId)"
        case .modelNotFound(let path):
            return "TTS model not found at: \(path)"
        case .invalidConfiguration(let reason):
            return "Invalid TTS configuration: \(reason)"
        case .invalidSpeakingRate(let value):
            return "Invalid speaking rate: \(value). Must be between 0.5 and 2.0."
        case .invalidPitch(let value):
            return "Invalid pitch: \(value). Must be between 0.5 and 2.0."
        case .invalidVolume(let value):
            return "Invalid volume: \(value). Must be between 0.0 and 1.0."
        case .emptyText:
            return "Cannot synthesize empty text."
        case .textTooLong(let max, let received):
            return "Text too long. Maximum \(max) characters allowed, received \(received)."
        case .invalidSSML(let reason):
            return "Invalid SSML markup: \(reason)"
        case .synthesisFailed(let reason):
            return "TTS synthesis failed: \(reason)"
        case .voiceNotAvailable(let voiceId):
            return "Voice not available: \(voiceId)"
        case .languageNotSupported(let language):
            return "Language not supported: \(language)"
        case .audioFormatNotSupported(let format):
            return "Audio format not supported: \(format)"
        case .insufficientMemory(let required, let available):
            return "Insufficient memory. Required: \(required) bytes, Available: \(available) bytes"
        case .cancelled:
            return "TTS operation was cancelled"
        case .busy:
            return "TTS service is busy with another operation"
        }
    }
}
