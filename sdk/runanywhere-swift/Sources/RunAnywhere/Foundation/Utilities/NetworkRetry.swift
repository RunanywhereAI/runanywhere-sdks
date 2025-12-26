//
//  NetworkRetry.swift
//  RunAnywhere SDK
//
//  Reusable async retry utility for network operations
//

import Foundation

/// Configuration for retry behavior
public struct RetryConfig {
    /// Maximum number of attempts (including initial attempt)
    public let maxAttempts: Int

    /// Delay between retries in seconds
    public let delaySeconds: Double

    /// Whether to use exponential backoff
    public let exponentialBackoff: Bool

    public static let `default` = RetryConfig(maxAttempts: 3, delaySeconds: 2.0, exponentialBackoff: false)
    public static let aggressive = RetryConfig(maxAttempts: 5, delaySeconds: 1.0, exponentialBackoff: true)

    public init(maxAttempts: Int, delaySeconds: Double, exponentialBackoff: Bool = false) {
        self.maxAttempts = maxAttempts
        self.delaySeconds = delaySeconds
        self.exponentialBackoff = exponentialBackoff
    }
}

/// Reusable retry utility for async operations
public enum NetworkRetry {

    private static let logger = SDKLogger(category: "NetworkRetry")

    /// Execute an async operation with retry logic
    /// - Parameters:
    ///   - config: Retry configuration
    ///   - operation: The async operation to execute
    /// - Returns: The result of the operation
    /// - Throws: The last error if all retries fail
    public static func execute<T>(
        config: RetryConfig = .default,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 1...config.maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error

                // Don't retry non-retryable errors
                guard isRetryable(error) else {
                    throw error
                }

                // Don't wait after the last attempt
                guard attempt < config.maxAttempts else {
                    break
                }

                let delay = config.exponentialBackoff
                    ? config.delaySeconds * pow(2.0, Double(attempt - 1))
                    : config.delaySeconds

                logger.debug("Attempt \(attempt) failed, retrying in \(delay)s: \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw lastError ?? SDKError.network(.requestFailed, "Operation failed after \(config.maxAttempts) attempts")
    }

    /// Execute an async operation with retry, returning nil on failure instead of throwing
    public static func executeOptional<T>(
        config: RetryConfig = .default,
        operation: () async throws -> T
    ) async -> T? {
        try? await execute(config: config, operation: operation)
    }

    /// Check if an error is retryable
    private static func isRetryable(_ error: Error) -> Bool {
        // SDKError (new unified error type)
        if let sdkError = error as? SDKError {
            switch sdkError.code {
            case .networkError, .timeout, .serverError, .networkUnavailable, .connectionLost:
                return true
            default:
                return false
            }
        }

        // URL errors
        if let nsError = error as NSError?, nsError.domain == NSURLErrorDomain {
            let retryableCodes = [
                NSURLErrorTimedOut,
                NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorNotConnectedToInternet,
                NSURLErrorDNSLookupFailed
            ]
            return retryableCodes.contains(nsError.code)
        }

        return false
    }
}
