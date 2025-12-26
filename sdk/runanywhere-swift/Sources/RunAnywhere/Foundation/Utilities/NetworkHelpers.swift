import Foundation

/// Helper for remote operations with timeout
public struct RemoteOperationHelper: Sendable {
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 10.0) {
        self.timeout = timeout
    }

    /// Execute operation with timeout (Swift 6 compliant)
    public func withTimeout<R: Sendable>(
        _ operation: @escaping @Sendable () async throws -> R
    ) async throws -> R {
        try await withThrowingTaskGroup(of: R.self) { group in
            // Add main operation
            group.addTask {
                try await operation()
            }

            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(self.timeout * 1_000_000_000))
                throw DataSourceError.networkUnavailable
            }

            // First completed task wins - guaranteed non-nil with 2 tasks
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

/// Errors that can occur in data sources
public enum DataSourceError: LocalizedError {
    case notAvailable
    case configurationInvalid(String)
    case networkUnavailable
    case authenticationFailed
    case entityNotFound(String)
    case operationFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Data source is not available"
        case .configurationInvalid(let message):
            return "Invalid configuration: \(message)"
        case .networkUnavailable:
            return "Network is unavailable"
        case .authenticationFailed:
            return "Authentication failed"
        case .entityNotFound(let id):
            return "Entity not found: \(id)"
        case .operationFailed(let error):
            return "Operation failed: \(error.localizedDescription)"
        }
    }
}
