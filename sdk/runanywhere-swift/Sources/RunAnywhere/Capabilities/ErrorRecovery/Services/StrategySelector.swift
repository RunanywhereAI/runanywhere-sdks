//
//  StrategySelector.swift
//  RunAnywhere SDK
//
//  Selects appropriate recovery strategy for errors
//

import Foundation

/// Selects the best recovery strategy for a given error
public class StrategySelector {

    // MARK: - Properties

    private let logger = SDKLogger(category: "StrategySelector")

    // MARK: - Public Methods

    /// Select the best strategy for an error
    public func selectStrategy(
        for error: Error,
        from strategies: [ErrorRecoveryStrategy]
    ) -> ErrorRecoveryStrategy? {

        // Find all applicable strategies
        let applicableStrategies = strategies.filter { $0.canRecover(from: error) }

        guard !applicableStrategies.isEmpty else {
            logger.warning("No applicable recovery strategies found")
            return nil
        }

        // If only one strategy, use it
        if applicableStrategies.count == 1 {
            return applicableStrategies.first
        }

        // Prioritize strategies based on error type
        let errorType = ErrorType(from: error)

        // Strategy selection logic based on error type
        switch errorType {
        case .network, .download:
            // Prefer retry strategy for network issues
            return applicableStrategies.first { $0 is RetryStrategy }
                ?? applicableStrategies.first

        case .memory:
            // Prefer framework switch for memory issues
            return applicableStrategies.first { $0 is FrameworkSwitchStrategy }
                ?? applicableStrategies.first { $0 is FallbackStrategy }
                ?? applicableStrategies.first

        case .framework:
            // Prefer framework switch or fallback
            return applicableStrategies.first { $0 is FrameworkSwitchStrategy }
                ?? applicableStrategies.first { $0 is FallbackStrategy }
                ?? applicableStrategies.first

        default:
            // Use first available strategy
            return applicableStrategies.first
        }
    }

    /// Score strategies based on context
    public func scoreStrategy(
        _ strategy: ErrorRecoveryStrategy,
        for error: Error,
        context: RecoveryContext
    ) -> Double {
        var score = 0.0

        // Base score if strategy can recover
        if strategy.canRecover(from: error) {
            score += 1.0
        }

        // Adjust based on attempt count
        if context.attemptCount > 1 {
            // Penalize retry strategies after multiple attempts
            if strategy is RetryStrategy {
                score -= Double(context.attemptCount) * 0.2
            }
        }

        // Adjust based on available resources
        if context.availableResources.memoryAvailable < 1_000_000_000 { // Less than 1GB
            // Prefer strategies that reduce memory usage
            if strategy is FrameworkSwitchStrategy {
                score += 0.5
            }
        }

        return max(0, score)
    }
}
