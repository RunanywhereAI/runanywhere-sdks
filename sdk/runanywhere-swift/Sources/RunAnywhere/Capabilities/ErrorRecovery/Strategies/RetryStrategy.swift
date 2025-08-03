//
//  RetryStrategy.swift
//  RunAnywhere SDK
//
//  Simple retry strategy for recoverable errors
//

import Foundation

/// Retry strategy for transient errors
public class RetryStrategy: ErrorRecoveryStrategy {

    // MARK: - Properties

    private let logger = SDKLogger(category: "RetryStrategy")

    // MARK: - ErrorRecoveryStrategy

    public func canRecover(from error: Error) -> Bool {
        let errorType = ErrorType(from: error)

        // Can retry network and download errors
        switch errorType {
        case .network, .download:
            return true
        case .memory:
            // Can retry memory errors if they might be transient
            return true
        default:
            return false
        }
    }

    public func recover(from error: Error, context: RecoveryContext) async throws {
        logger.info("Attempting retry recovery for error: \(error.localizedDescription)")

        // Check if retries are exhausted
        if context.attemptCount >= context.options.maxRetryAttempts {
            logger.error("Max retry attempts reached")
            throw UnifiedModelError.retryRequired("Max retry attempts exceeded")
        }

        // For this strategy, we just signal that a retry should be attempted
        // The actual retry logic is handled by the calling code
        throw UnifiedModelError.retryRequired("Retry attempt \(context.attemptCount + 1)")
    }

    public func getRecoverySuggestions(for error: Error) -> [RecoverySuggestion] {
        var suggestions: [RecoverySuggestion] = []

        let errorType = ErrorType(from: error)

        switch errorType {
        case .network:
            suggestions.append(RecoverySuggestion(
                action: .retry,
                description: "Retry the network request",
                priority: .high,
                estimatedDuration: 5.0
            ))

            suggestions.append(RecoverySuggestion(
                action: .retryWithDelay(30.0),
                description: "Wait 30 seconds and retry",
                priority: .medium,
                estimatedDuration: 35.0
            ))

        case .download:
            suggestions.append(RecoverySuggestion(
                action: .retry,
                description: "Resume download",
                priority: .high,
                estimatedDuration: nil
            ))

            suggestions.append(RecoverySuggestion(
                action: .downloadAlternative,
                description: "Try alternative download source",
                priority: .medium,
                estimatedDuration: nil
            ))

        case .memory:
            suggestions.append(RecoverySuggestion(
                action: .freeMemory,
                description: "Free memory and retry",
                priority: .high,
                estimatedDuration: 2.0
            ))

            suggestions.append(RecoverySuggestion(
                action: .clearCache,
                description: "Clear cache and retry",
                priority: .medium,
                estimatedDuration: 5.0
            ))

        default:
            suggestions.append(RecoverySuggestion(
                action: .retry,
                description: "Retry the operation",
                priority: .low,
                estimatedDuration: nil
            ))
        }

        return suggestions
    }
}
