//
//  ErrorCategory.swift
//  RunAnywhere SDK
//
//  Error category classification for grouping and filtering errors
//

import Foundation

/// Error categories for logical grouping and filtering
public enum ErrorCategory: String, Sendable, CaseIterable {
    case initialization
    case model
    case generation
    case network
    case storage
    case memory
    case hardware
    case validation
    case authentication
    case component
    case framework
    case unknown

    /// Initialize from an error by analyzing its type and message
    public init(from error: Error) {
        // Check for known error types first
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
                self = ErrorCategory.categorizeFromDescription(error.localizedDescription)
            }
        default:
            self = ErrorCategory.categorizeFromDescription(error.localizedDescription)
        }
    }

    /// Categorize based on error description keywords
    private static func categorizeFromDescription(_ description: String) -> ErrorCategory {
        let lowercased = description.lowercased()

        if lowercased.contains("memory") || lowercased.contains("out of memory") {
            return .memory
        } else if lowercased.contains("download") || lowercased.contains("network") || lowercased.contains("connection") {
            return .network
        } else if lowercased.contains("validation") || lowercased.contains("invalid") || lowercased.contains("checksum") {
            return .validation
        } else if lowercased.contains("hardware") || lowercased.contains("device") || lowercased.contains("thermal") {
            return .hardware
        } else if lowercased.contains("auth") || lowercased.contains("credential") || lowercased.contains("api key") {
            return .authentication
        } else if lowercased.contains("model") || lowercased.contains("load") {
            return .model
        } else if lowercased.contains("storage") || lowercased.contains("disk") || lowercased.contains("space") {
            return .storage
        } else if lowercased.contains("initialize") || lowercased.contains("not initialized") {
            return .initialization
        } else if lowercased.contains("component") {
            return .component
        } else if lowercased.contains("framework") {
            return .framework
        } else if lowercased.contains("generation") || lowercased.contains("generate") {
            return .generation
        }

        return .unknown
    }
}

// MARK: - Backward Compatibility

/// Type alias for backward compatibility with existing code
@available(*, deprecated, renamed: "ErrorCategory")
public typealias ErrorType = ErrorCategory
