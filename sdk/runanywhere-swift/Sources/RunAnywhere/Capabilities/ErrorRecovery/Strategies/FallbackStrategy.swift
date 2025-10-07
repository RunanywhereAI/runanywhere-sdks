//
//  FallbackStrategy.swift
//  RunAnywhere SDK
//
//  Fallback to alternative options
//

import Foundation

/// Fallback strategy for using alternative options
public class FallbackStrategy: ErrorRecoveryStrategy {

    // MARK: - Properties

    private let logger = SDKLogger(category: "FallbackStrategy")

    // MARK: - ErrorRecoveryStrategy

    public func canRecover(from error: Error) -> Bool {
        // Can provide fallback for most error types
        let errorType = ErrorType(from: error)

        switch errorType {
        case .validation, .hardware, .authentication:
            // Cannot fallback for these
            return false
        default:
            return true
        }
    }

    public func recover(from error: Error, context: RecoveryContext) async throws {
        logger.info("Attempting fallback recovery for error: \(error.localizedDescription)")

        let errorType = ErrorType(from: error)

        switch errorType {
        case .download:
            // Fallback to cached version if available
            logger.info("Checking for cached model version")
            throw UnifiedModelError.retryRequired("Check cache for model")

        case .framework:
            // Fallback handled by framework switch strategy
            throw UnifiedModelError.retryRequired("Framework fallback needed")

        case .memory:
            // Fallback to reduced quality
            if context.options.allowQualityReduction {
                logger.info("Falling back to reduced quality mode")
                throw UnifiedModelError.retryRequired("Use reduced quality")
            } else {
                throw UnifiedModelError.unrecoverable(error)
            }

        case .network:
            // Fallback to offline mode if possible
            logger.info("Falling back to offline mode")
            throw UnifiedModelError.retryRequired("Use offline mode")

        case .configuration:
            // Fallback to default configuration
            logger.info("Falling back to default configuration")
            throw UnifiedModelError.retryRequired("Use default configuration")

        default:
            throw UnifiedModelError.unrecoverable(error)
        }
    }

    public func getRecoverySuggestions(for error: Error) -> [RecoverySuggestion] {
        var suggestions: [RecoverySuggestion] = []

        let errorType = ErrorType(from: error)

        switch errorType {
        case .download:
            suggestions.append(RecoverySuggestion(
                action: .downloadAlternative,
                description: "Use alternative download source",
                priority: .high
            ))

        case .framework:
            // Framework switch handled by dedicated strategy
            break

        case .memory:
            suggestions.append(RecoverySuggestion(
                action: .reduceQuality,
                description: "Use lower quality model",
                priority: .medium
            ))

        case .network:
            suggestions.append(RecoverySuggestion(
                action: .updateConfiguration,
                description: "Switch to offline mode",
                priority: .high
            ))

        case .configuration:
            suggestions.append(RecoverySuggestion(
                action: .updateConfiguration,
                description: "Reset to default configuration",
                priority: .medium
            ))

        default:
            break
        }

        // Always suggest contacting support as last resort
        suggestions.append(RecoverySuggestion(
            action: .contactSupport,
            description: "Contact support for assistance",
            priority: .low
        ))

        return suggestions
    }
}
