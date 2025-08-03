//
//  ABTestError.swift
//  RunAnywhere SDK
//
//  A/B test error types
//

import Foundation

/// A/B test errors
public enum ABTestError: LocalizedError {
    case testNotFound
    case testNotRunning
    case insufficientData
    case invalidConfiguration

    public var errorDescription: String? {
        switch self {
        case .testNotFound:
            return "A/B test not found"
        case .testNotRunning:
            return "A/B test is not running"
        case .insufficientData:
            return "Insufficient data for analysis"
        case .invalidConfiguration:
            return "Invalid test configuration"
        }
    }
}
