//
//  ErrorType.swift
//  RunAnywhere SDK
//
//  Error type categorization
//

import Foundation

/// Error types for categorization
public enum ErrorType {
    case download
    case network
    case memory
    case validation
    case framework
    case hardware
    case configuration
    case authentication
    case unknown

    /// Initialize from an error
    public init(from error: Error) {
        // Categorize based on error type
        switch error {
        case is URLError:
            self = .network
        case let nsError as NSError:
            switch nsError.domain {
            case NSURLErrorDomain:
                self = .network
            case NSPOSIXErrorDomain where nsError.code == ENOMEM:
                self = .memory
            default:
                self = .unknown
            }
        default:
            // Check error description for hints
            let description = error.localizedDescription.lowercased()
            if description.contains("memory") {
                self = .memory
            } else if description.contains("download") {
                self = .download
            } else if description.contains("validation") || description.contains("checksum") {
                self = .validation
            } else if description.contains("hardware") || description.contains("device") {
                self = .hardware
            } else if description.contains("auth") || description.contains("credential") {
                self = .authentication
            } else {
                self = .unknown
            }
        }
    }
}
