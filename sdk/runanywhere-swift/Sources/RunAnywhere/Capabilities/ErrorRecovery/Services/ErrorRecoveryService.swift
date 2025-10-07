//
//  ErrorRecoveryService.swift
//  RunAnywhere SDK
//
//  Main error recovery coordination service
//

import Foundation

/// Service for coordinating error recovery
public class ErrorRecoveryService {

    // MARK: - Properties

    /// Available recovery strategies
    private let strategies: [ErrorRecoveryStrategy]

    /// Strategy selector
    private let strategySelector: StrategySelector

    /// Recovery executor
    private let recoveryExecutor: RecoveryExecutor

    /// Logger
    private let logger = SDKLogger(category: "ErrorRecovery")

    // MARK: - Initialization

    public init(
        strategies: [ErrorRecoveryStrategy]? = nil,
        strategySelector: StrategySelector? = nil,
        recoveryExecutor: RecoveryExecutor? = nil
    ) {
        self.strategies = strategies ?? Self.defaultStrategies()
        self.strategySelector = strategySelector ?? StrategySelector()
        self.recoveryExecutor = recoveryExecutor ?? RecoveryExecutor()
    }

    // MARK: - Public Methods

    /// Check if recovery is possible for an error
    public func canRecover(from error: Error) -> Bool {
        return strategies.contains { $0.canRecover(from: error) }
    }

    /// Attempt to recover from an error
    public func recover(from error: Error, context: RecoveryContext) async throws {
        logger.info("Attempting recovery from error: \(error.localizedDescription)")

        // Select appropriate strategy
        guard let strategy = strategySelector.selectStrategy(for: error, from: strategies) else {
            logger.error("No recovery strategy found for error")
            throw UnifiedModelError.unrecoverable(error)
        }

        logger.info("Selected recovery strategy: \(String(describing: type(of: strategy)))")

        // Execute recovery
        do {
            try await recoveryExecutor.execute(strategy: strategy, error: error, context: context)
            logger.info("Recovery successful")
        } catch {
            logger.error("Recovery failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Get recovery suggestions for an error
    public func getRecoverySuggestions(for error: Error) -> [RecoverySuggestion] {
        return strategies
            .filter { $0.canRecover(from: error) }
            .flatMap { $0.getRecoverySuggestions(for: error) }
            .sorted { $0.priority.rawValue > $1.priority.rawValue }
    }

    // MARK: - Private Methods

    private static func defaultStrategies() -> [ErrorRecoveryStrategy] {
        return [
            RetryStrategy(),
            FallbackStrategy(),
            FrameworkSwitchStrategy()
        ]
    }
}

// MARK: - Priority Extension

private extension RecoverySuggestion.Priority {
    var rawValue: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .critical: return 3
        }
    }
}
