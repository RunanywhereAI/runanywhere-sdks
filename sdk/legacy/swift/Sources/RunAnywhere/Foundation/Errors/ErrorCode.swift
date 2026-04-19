//
//  ErrorCode.swift
//  RunAnywhere
//
//  Created by RunAnywhere on 2024.
//

import Foundation

/// All possible error codes in the SDK.
/// The code serves as a unique identifier for each error type.
public enum ErrorCode: String, Sendable, CaseIterable {
    // MARK: - Initialization Errors

    /// Component or service has not been initialized
    case notInitialized

    /// Component or service is already initialized
    case alreadyInitialized

    /// Initialization failed
    case initializationFailed

    /// Configuration is invalid
    case invalidConfiguration

    /// API key is invalid or missing
    case invalidAPIKey

    /// Environment mismatch (e.g., dev vs prod)
    case environmentMismatch

    // MARK: - Model Errors

    /// Requested model was not found
    case modelNotFound

    /// Failed to load the model
    case modelLoadFailed

    /// Model validation failed
    case modelValidationFailed

    /// Model is incompatible with current runtime
    case modelIncompatible

    /// Model format is invalid
    case invalidModelFormat

    /// Model storage is corrupted
    case modelStorageCorrupted

    // MARK: - Generation Errors

    /// Text/audio generation failed
    case generationFailed

    /// Generation timed out
    case generationTimeout

    /// Context length exceeded maximum
    case contextTooLong

    /// Token limit exceeded
    case tokenLimitExceeded

    /// Cost limit exceeded
    case costLimitExceeded

    // MARK: - Network Errors

    /// Network is unavailable
    case networkUnavailable

    /// Generic network error
    case networkError

    /// Request failed
    case requestFailed

    /// Download failed
    case downloadFailed

    /// Server returned an error
    case serverError

    /// Request timed out
    case timeout

    /// Invalid response from server
    case invalidResponse

    /// HTTP error with status code
    case httpError

    /// Connection was lost
    case connectionLost

    /// Partial download (incomplete)
    case partialDownload

    // MARK: - Storage Errors

    /// Insufficient storage space
    case insufficientStorage

    /// Storage is full
    case storageFull

    /// Generic storage error
    case storageError

    /// File was not found
    case fileNotFound

    /// Failed to read file
    case fileReadFailed

    /// Failed to write file
    case fileWriteFailed

    /// Permission denied for file operation
    case permissionDenied

    /// Failed to delete file or directory
    case deleteFailed

    /// Failed to move file
    case moveFailed

    /// Failed to create directory
    case directoryCreationFailed

    /// Directory not found
    case directoryNotFound

    /// Invalid file path
    case invalidPath

    /// Invalid file name
    case invalidFileName

    /// Failed to create temporary file
    case tempFileCreationFailed

    // MARK: - Hardware Errors

    /// Hardware is unsupported
    case hardwareUnsupported

    /// Insufficient memory
    case insufficientMemory

    // MARK: - Component State Errors

    /// Component is not ready
    case componentNotReady

    /// Component is in invalid state
    case invalidState

    /// Service is not available
    case serviceNotAvailable

    /// Service is busy
    case serviceBusy

    /// Processing failed
    case processingFailed

    /// Start operation failed
    case startFailed

    /// Feature/operation is not supported
    case notSupported

    // MARK: - Validation Errors

    /// Validation failed
    case validationFailed

    /// Input is invalid
    case invalidInput

    /// Format is invalid
    case invalidFormat

    /// Input is empty
    case emptyInput

    /// Text is too long
    case textTooLong

    /// Invalid SSML markup
    case invalidSSML

    /// Invalid speaking rate
    case invalidSpeakingRate

    /// Invalid pitch
    case invalidPitch

    /// Invalid volume
    case invalidVolume

    // MARK: - Audio Errors

    /// Audio format is not supported
    case audioFormatNotSupported

    /// Audio session configuration failed
    case audioSessionFailed

    /// Microphone permission denied
    case microphonePermissionDenied

    /// Insufficient audio data
    case insufficientAudioData

    /// Audio buffer is empty
    case emptyAudioBuffer

    /// Audio session activation failed
    case audioSessionActivationFailed

    // MARK: - Language/Voice Errors

    /// Language is not supported
    case languageNotSupported

    /// Voice is not available
    case voiceNotAvailable

    /// Streaming is not supported
    case streamingNotSupported

    /// Stream was cancelled
    case streamCancelled

    // MARK: - Authentication Errors

    /// Authentication failed
    case authenticationFailed

    /// Unauthorized access
    case unauthorized

    /// Access forbidden
    case forbidden

    // MARK: - Security Errors

    /// Keychain operation failed
    case keychainError

    /// Encoding error
    case encodingError

    /// Decoding error
    case decodingError

    // MARK: - Extraction Errors

    /// Extraction failed (JSON, archive, etc.)
    case extractionFailed

    /// Checksum mismatch
    case checksumMismatch

    /// Unsupported archive format
    case unsupportedArchive

    // MARK: - Calibration Errors

    /// Calibration failed
    case calibrationFailed

    /// Calibration timed out
    case calibrationTimeout

    // MARK: - Cancellation

    /// Operation was cancelled
    case cancelled

    // MARK: - Other Errors

    /// Feature is not implemented
    case notImplemented

    /// Feature is not available
    case featureNotAvailable

    /// Framework is not available
    case frameworkNotAvailable

    /// Unsupported modality
    case unsupportedModality

    /// Unknown error
    case unknown
}

// MARK: - Error Classification

extension ErrorCode {

    /// Whether this error is expected/routine and shouldn't be logged as an error.
    /// Examples: user cancellation, stream cancellation
    public var isExpected: Bool {
        switch self {
        case .cancelled, .streamCancelled:
            return true
        default:
            return false
        }
    }
}
