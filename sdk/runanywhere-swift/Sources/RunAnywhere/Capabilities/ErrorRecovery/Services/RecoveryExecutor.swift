//
//  RecoveryExecutor.swift
//  RunAnywhere SDK
//
//  Executes error recovery strategies
//

import Foundation

/// Executes recovery strategies with proper error handling
public class RecoveryExecutor {

    // MARK: - Properties

    private let logger = SDKLogger(category: "RecoveryExecutor")

    // MARK: - Public Methods

    /// Execute a recovery strategy
    public func execute(
        strategy: ErrorRecoveryStrategy,
        error: Error,
        context: RecoveryContext
    ) async throws {

        logger.info("Executing recovery strategy: \(String(describing: type(of: strategy)))")

        // Check retry limit
        if context.attemptCount > context.options.maxRetryAttempts {
            logger.error("Max retry attempts exceeded (\(context.options.maxRetryAttempts))")
            throw UnifiedModelError.unrecoverable(error)
        }

        // Apply retry delay if needed
        if context.attemptCount > 1 {
            let delay = calculateDelay(
                attempt: context.attemptCount,
                baseDelay: context.options.retryDelay,
                exponential: context.options.exponentialBackoff
            )

            logger.info("Waiting \(delay) seconds before retry")
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        // Execute strategy
        do {
            try await strategy.recover(from: error, context: context)
        } catch {
            // Log failure and re-throw
            logger.error("Recovery strategy failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Execute multiple strategies in sequence
    public func executeSequence(
        strategies: [ErrorRecoveryStrategy],
        error: Error,
        context: RecoveryContext
    ) async throws {

        var lastError: Error = error
        var attemptContext = context

        for strategy in strategies {
            do {
                try await execute(
                    strategy: strategy,
                    error: lastError,
                    context: attemptContext
                )
                // Success - return early
                return
            } catch {
                // Update context for next attempt
                lastError = error
                attemptContext = RecoveryContext(
                    model: context.model,
                    stage: context.stage,
                    attemptCount: attemptContext.attemptCount + 1,
                    previousErrors: attemptContext.previousErrors + [error],
                    availableResources: context.availableResources,
                    options: context.options
                )
            }
        }

        // All strategies failed
        throw UnifiedModelError.unrecoverable(lastError)
    }

    // MARK: - Private Methods

    private func calculateDelay(
        attempt: Int,
        baseDelay: TimeInterval,
        exponential: Bool
    ) -> TimeInterval {
        if exponential {
            // Exponential backoff: delay * 2^(attempt-1)
            return baseDelay * pow(2.0, Double(attempt - 1))
        } else {
            // Linear delay
            return baseDelay * Double(attempt)
        }
    }
}
