//
//  RecoverySuggestion.swift
//  RunAnywhere SDK
//
//  Recovery action suggestions
//

import Foundation

/// Recovery suggestion
public struct RecoverySuggestion {
    public let action: RecoveryAction
    public let description: String
    public let priority: Priority
    public let estimatedDuration: TimeInterval?

    public enum RecoveryAction {
        case retry
        case retryWithDelay(TimeInterval)
        case switchFramework(LLMFramework)
        case reduceQuality
        case clearCache
        case freeMemory
        case downloadAlternative
        case updateConfiguration
        case contactSupport
    }

    public enum Priority {
        case low
        case medium
        case high
        case critical
    }

    public init(
        action: RecoveryAction,
        description: String,
        priority: Priority = .medium,
        estimatedDuration: TimeInterval? = nil
    ) {
        self.action = action
        self.description = description
        self.priority = priority
        self.estimatedDuration = estimatedDuration
    }
}
