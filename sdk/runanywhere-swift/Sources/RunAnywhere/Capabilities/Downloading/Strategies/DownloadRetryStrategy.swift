import Foundation

/// Strategy for handling download retries
public class DownloadRetryStrategy {

    // MARK: - Properties

    private let maxRetries: Int
    private let baseDelay: TimeInterval
    private let maxDelay: TimeInterval
    private let backoffMultiplier: Double
    private let logger = SDKLogger(category: "RetryStrategy")

    // MARK: - Initialization

    public init(
        maxRetries: Int = 3,
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 60.0,
        backoffMultiplier: Double = 2.0
    ) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.backoffMultiplier = backoffMultiplier
    }

    // MARK: - Public Methods

    /// Execute an operation with retry logic
    public func executeWithRetry<T>(
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                logger.debug("Executing operation, attempt \(attempt + 1) of \(maxRetries)")
                return try await operation()
            } catch {
                lastError = error

                // Check if error is retryable
                guard isRetryable(error) else {
                    logger.error("Non-retryable error: \(error)")
                    throw error
                }

                // Calculate delay for next attempt
                if attempt < maxRetries - 1 {
                    let delay = calculateDelay(for: attempt)
                    logger.info("Retrying after \(delay) seconds. Error: \(error)")

                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        logger.error("Max retries (\(maxRetries)) exceeded")
        throw lastError ?? DownloadError.maxRetriesExceeded
    }

    // MARK: - Private Methods

    private func isRetryable(_ error: Error) -> Bool {
        // Check for specific retryable errors
        if let downloadError = error as? DownloadError {
            switch downloadError {
            case .networkError, .timeout, .connectionLost, .partialDownload:
                return true
            case .invalidURL, .invalidResponse, .checksumMismatch, .insufficientSpace:
                return false
            default:
                return false
            }
        }

        // Check for URLError
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }

        // Check for NSError
        if let nsError = error as NSError? {
            // Network-related errors
            if nsError.domain == NSURLErrorDomain {
                let retryableCodes = [
                    NSURLErrorTimedOut,
                    NSURLErrorNetworkConnectionLost,
                    NSURLErrorNotConnectedToInternet,
                    NSURLErrorCannotConnectToHost
                ]
                return retryableCodes.contains(nsError.code)
            }
        }

        return false
    }

    private func calculateDelay(for attempt: Int) -> TimeInterval {
        // Exponential backoff with jitter
        let exponentialDelay = baseDelay * pow(backoffMultiplier, Double(attempt))
        let jitter = Double.random(in: 0.8...1.2)
        let delay = min(exponentialDelay * jitter, maxDelay)

        return delay
    }
}

// MARK: - Download Error Extension

extension DownloadError {
    static let maxRetriesExceeded = DownloadError.networkError(
        NSError(domain: "RetryStrategy", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Maximum retry attempts exceeded"
        ])
    )
}
