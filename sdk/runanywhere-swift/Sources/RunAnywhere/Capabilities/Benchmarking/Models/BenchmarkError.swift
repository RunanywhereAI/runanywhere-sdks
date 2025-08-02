//
//  BenchmarkError.swift
//  RunAnywhere SDK
//
//  Benchmark error types
//

import Foundation

/// Benchmark errors
public enum BenchmarkError: LocalizedError {
    case alreadyRunning
    case noServicesProvided
    case serviceInitializationFailed
    case invalidConfiguration

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "A benchmark is already running"
        case .noServicesProvided:
            return "No services provided for benchmarking"
        case .serviceInitializationFailed:
            return "Failed to initialize service for benchmarking"
        case .invalidConfiguration:
            return "Invalid benchmark configuration"
        }
    }
}
