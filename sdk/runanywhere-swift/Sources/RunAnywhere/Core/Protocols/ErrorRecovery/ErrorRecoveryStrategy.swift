//
//  ErrorRecoveryStrategy.swift
//  RunAnywhere SDK
//
//  Protocol for error recovery strategies
//

import Foundation

/// Protocol for error recovery strategies
public protocol ErrorRecoveryStrategy {
    /// Check if this strategy can recover from the error
    /// - Parameter error: The error to check
    /// - Returns: Whether recovery is possible
    func canRecover(from error: Error) -> Bool

    /// Attempt to recover from the error
    /// - Parameters:
    ///   - error: The error to recover from
    ///   - context: Recovery context
    func recover(from error: Error, context: RecoveryContext) async throws

    /// Get recovery suggestions
    /// - Parameter error: The error
    /// - Returns: Suggested recovery actions
    func getRecoverySuggestions(for error: Error) -> [RecoverySuggestion]
}
