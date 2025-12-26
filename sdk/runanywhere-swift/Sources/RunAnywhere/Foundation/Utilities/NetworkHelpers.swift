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
                throw SDKError.network(.timeout, "Operation timed out after \(self.timeout) seconds")
            }

            // First completed task wins - guaranteed non-nil with 2 tasks
            guard let result = try await group.next() else {
                throw SDKError.network(.requestFailed, "No result from task group")
            }
            group.cancelAll()
            return result
        }
    }
}
