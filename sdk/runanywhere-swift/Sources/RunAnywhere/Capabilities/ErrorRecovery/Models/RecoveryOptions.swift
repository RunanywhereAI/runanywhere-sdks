//
//  RecoveryOptions.swift
//  RunAnywhere SDK
//
//  Options for error recovery strategies
//

import Foundation

/// Recovery options
public struct RecoveryOptions {
    public let maxRetryAttempts: Int
    public let retryDelay: TimeInterval
    public let exponentialBackoff: Bool
    public let allowFrameworkSwitch: Bool
    public let allowQualityReduction: Bool
    public let allowMemoryOptimization: Bool

    public init(
        maxRetryAttempts: Int = 3,
        retryDelay: TimeInterval = 1.0,
        exponentialBackoff: Bool = true,
        allowFrameworkSwitch: Bool = true,
        allowQualityReduction: Bool = false,
        allowMemoryOptimization: Bool = true
    ) {
        self.maxRetryAttempts = maxRetryAttempts
        self.retryDelay = retryDelay
        self.exponentialBackoff = exponentialBackoff
        self.allowFrameworkSwitch = allowFrameworkSwitch
        self.allowQualityReduction = allowQualityReduction
        self.allowMemoryOptimization = allowMemoryOptimization
    }
}
