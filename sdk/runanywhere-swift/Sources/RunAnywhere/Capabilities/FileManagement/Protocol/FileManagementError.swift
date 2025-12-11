//
//  FileManagementError.swift
//  RunAnywhere SDK
//
//  Typed errors specific to file management operations
//  Provides detailed error cases for file operations, storage issues, and model file handling
//

import Foundation

/// Errors that can occur during file management operations
public enum FileManagementError: Error, LocalizedError, Sendable {

    // MARK: - Directory Errors

    /// Unable to access or create a directory
    case directoryAccessFailed(path: String, underlying: Error?)

    /// Directory not found at specified path
    case directoryNotFound(path: String)

    /// Unable to create directory
    case directoryCreationFailed(path: String, reason: String)

    // MARK: - File Errors

    /// File not found at specified path
    case fileNotFound(path: String)

    /// Unable to read file
    case fileReadFailed(path: String, underlying: Error?)

    /// Unable to write file
    case fileWriteFailed(path: String, underlying: Error?)

    /// Unable to delete file or directory
    case deleteFailed(path: String, underlying: Error?)

    /// File operation not permitted
    case permissionDenied(path: String)

    // MARK: - Model Storage Errors

    /// Model file not found
    case modelNotFound(modelId: String)

    /// Model folder not accessible
    case modelFolderAccessFailed(modelId: String, underlying: Error?)

    /// Invalid model format
    case invalidModelFormat(expected: String, received: String)

    /// Model storage corrupted
    case modelStorageCorrupted(modelId: String, reason: String)

    // MARK: - Storage Space Errors

    /// Insufficient storage space
    case insufficientSpace(required: Int64, available: Int64)

    /// Storage full
    case storageFull

    /// Unable to determine available space
    case storageInfoUnavailable(reason: String)

    // MARK: - Cache Errors

    /// Cache key not found
    case cacheKeyNotFound(key: String)

    /// Cache write failed
    case cacheWriteFailed(key: String, underlying: Error?)

    /// Cache read failed
    case cacheReadFailed(key: String, underlying: Error?)

    // MARK: - Download Errors

    /// Download folder not accessible
    case downloadFolderAccessFailed(underlying: Error?)

    /// Temporary file creation failed
    case tempFileCreationFailed(reason: String)

    /// Move operation failed
    case moveFailed(from: String, to: String, underlying: Error?)

    // MARK: - Validation Errors

    /// Invalid path provided
    case invalidPath(path: String, reason: String)

    /// Invalid file name
    case invalidFileName(fileName: String, reason: String)

    /// Model validation failed
    case modelValidationFailed(modelId: String, reason: String)

    // MARK: - Generic Errors

    /// Unknown file system error
    case unknown(underlying: Error)

    // MARK: - LocalizedError Conformance

    public var errorDescription: String? {
        switch self {
        // Directory errors
        case .directoryAccessFailed(let path, let error):
            if let error = error {
                return "Failed to access directory at '\(path)': \(error.localizedDescription)"
            }
            return "Failed to access directory at '\(path)'"
        case .directoryNotFound(let path):
            return "Directory not found at '\(path)'"
        case .directoryCreationFailed(let path, let reason):
            return "Failed to create directory at '\(path)': \(reason)"

        // File errors
        case .fileNotFound(let path):
            return "File not found at '\(path)'"
        case .fileReadFailed(let path, let error):
            if let error = error {
                return "Failed to read file at '\(path)': \(error.localizedDescription)"
            }
            return "Failed to read file at '\(path)'"
        case .fileWriteFailed(let path, let error):
            if let error = error {
                return "Failed to write file at '\(path)': \(error.localizedDescription)"
            }
            return "Failed to write file at '\(path)'"
        case .deleteFailed(let path, let error):
            if let error = error {
                return "Failed to delete '\(path)': \(error.localizedDescription)"
            }
            return "Failed to delete '\(path)'"
        case .permissionDenied(let path):
            return "Permission denied for '\(path)'"

        // Model storage errors
        case .modelNotFound(let modelId):
            return "Model '\(modelId)' not found in storage"
        case .modelFolderAccessFailed(let modelId, let error):
            if let error = error {
                return "Failed to access model folder for '\(modelId)': \(error.localizedDescription)"
            }
            return "Failed to access model folder for '\(modelId)'"
        case .invalidModelFormat(let expected, let received):
            return "Invalid model format. Expected '\(expected)', received '\(received)'"
        case .modelStorageCorrupted(let modelId, let reason):
            return "Model storage for '\(modelId)' is corrupted: \(reason)"

        // Storage space errors
        case .insufficientSpace(let required, let available):
            let formatter = ByteCountFormatter()
            let requiredStr = formatter.string(fromByteCount: required)
            let availableStr = formatter.string(fromByteCount: available)
            return "Insufficient storage space. Required: \(requiredStr), Available: \(availableStr)"
        case .storageFull:
            return "Device storage is full"
        case .storageInfoUnavailable(let reason):
            return "Unable to determine storage information: \(reason)"

        // Cache errors
        case .cacheKeyNotFound(let key):
            return "Cache entry not found for key '\(key)'"
        case .cacheWriteFailed(let key, let error):
            if let error = error {
                return "Failed to write cache for key '\(key)': \(error.localizedDescription)"
            }
            return "Failed to write cache for key '\(key)'"
        case .cacheReadFailed(let key, let error):
            if let error = error {
                return "Failed to read cache for key '\(key)': \(error.localizedDescription)"
            }
            return "Failed to read cache for key '\(key)'"

        // Download errors
        case .downloadFolderAccessFailed(let error):
            if let error = error {
                return "Failed to access download folder: \(error.localizedDescription)"
            }
            return "Failed to access download folder"
        case .tempFileCreationFailed(let reason):
            return "Failed to create temporary file: \(reason)"
        case .moveFailed(let from, let to, let error):
            if let error = error {
                return "Failed to move from '\(from)' to '\(to)': \(error.localizedDescription)"
            }
            return "Failed to move from '\(from)' to '\(to)'"

        // Validation errors
        case .invalidPath(let path, let reason):
            return "Invalid path '\(path)': \(reason)"
        case .invalidFileName(let fileName, let reason):
            return "Invalid file name '\(fileName)': \(reason)"
        case .modelValidationFailed(let modelId, let reason):
            return "Model validation failed for '\(modelId)': \(reason)"

        // Generic errors
        case .unknown(let error):
            return "File management error: \(error.localizedDescription)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .directoryAccessFailed, .directoryNotFound, .directoryCreationFailed:
            return "Ensure the application has proper file system permissions and the path is valid."
        case .fileNotFound:
            return "Verify the file exists at the specified path."
        case .fileReadFailed, .fileWriteFailed:
            return "Check file permissions and ensure the file is not corrupted."
        case .deleteFailed:
            return "Ensure the file is not in use and you have permission to delete it."
        case .permissionDenied:
            return "Grant the application necessary file system permissions."
        case .modelNotFound:
            return "Download the model first or check the model identifier."
        case .modelFolderAccessFailed:
            return "Ensure the model folder is accessible and not corrupted."
        case .invalidModelFormat:
            return "Ensure you're using the correct model format for your framework."
        case .modelStorageCorrupted:
            return "Delete and re-download the model."
        case .insufficientSpace, .storageFull:
            return "Free up storage space on your device."
        case .storageInfoUnavailable:
            return "Restart the application or check file system permissions."
        case .cacheKeyNotFound:
            return "The cache entry may have been cleared or never existed."
        case .cacheWriteFailed, .cacheReadFailed:
            return "Check available storage space and file permissions."
        case .downloadFolderAccessFailed:
            return "Ensure the download folder is accessible and not corrupted."
        case .tempFileCreationFailed:
            return "Check available storage space and permissions."
        case .moveFailed:
            return "Ensure both source and destination paths are valid and accessible."
        case .invalidPath, .invalidFileName:
            return "Provide a valid path or file name."
        case .modelValidationFailed:
            return "Ensure the model file is complete and not corrupted."
        case .unknown:
            return "Try again or contact support if the issue persists."
        }
    }
}
