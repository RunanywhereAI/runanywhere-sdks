//
//  LoggingError.swift
//  RunAnywhere SDK
//
//  Typed error enum for logging operations
//

import Foundation

/// Errors that can occur during logging operations
public enum LoggingError: Error, LocalizedError, Sendable {

    // MARK: - Configuration Errors

    /// Invalid logging configuration provided
    case invalidConfiguration(reason: String)

    // MARK: - Destination Errors

    /// Log destination is not available
    case destinationUnavailable(name: String)

    /// Failed to write to log destination
    case destinationWriteFailed(name: String, underlying: Error)

    /// No destinations configured
    case noDestinationsConfigured

    // MARK: - Runtime Errors

    /// Logging service not initialized
    case notInitialized

    /// Flush operation failed
    case flushFailed(underlying: Error)

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let reason):
            return "Invalid logging configuration: \(reason)"
        case .destinationUnavailable(let name):
            return "Log destination '\(name)' is not available"
        case .destinationWriteFailed(let name, let error):
            return "Failed to write to log destination '\(name)': \(error.localizedDescription)"
        case .noDestinationsConfigured:
            return "No log destinations configured"
        case .notInitialized:
            return "Logging service not initialized"
        case .flushFailed(let error):
            return "Failed to flush logs: \(error.localizedDescription)"
        }
    }
}
