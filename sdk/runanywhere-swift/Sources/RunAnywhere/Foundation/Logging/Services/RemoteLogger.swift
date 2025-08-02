//
//  RemoteLogger.swift
//  RunAnywhere SDK
//
//  Handles remote log submission to telemetry endpoint
//

import Foundation

/// Handles remote submission of log batches
internal class RemoteLogger {

    // MARK: - Properties

    /// URL session for network requests
    private let session: URLSession

    /// Current SDK version
    private let sdkVersion = "1.0.0" // TODO: Get from build configuration

    /// Session identifier
    private let sessionId: String

    /// Queue for failed log entries to retry
    private var retryQueue: [LogEntry] = []
    private let retryQueueLock = NSLock()

    // MARK: - Initialization

    init() {
        self.sessionId = UUID().uuidString

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Public Methods

    /// Submit a batch of logs to the remote endpoint
    func submitLogs(_ logs: [LogEntry], endpoint: URL) async {
        // Include any previously failed logs
        let allLogs = getRetryLogs() + logs
        guard !allLogs.isEmpty else { return }

        // Create batch payload
        let batch = LogBatch(
            logs: allLogs,
            sessionId: sessionId,
            sdkVersion: sdkVersion
        )

        do {
            // Prepare request
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("RunAnywhereSDK/\(sdkVersion)", forHTTPHeaderField: "User-Agent")

            // Encode payload
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(batch)

            // Send request
            let (_, response) = try await session.data(for: request)

            // Check response
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                    // Success - clear retry queue
                    clearRetryLogs()
                } else {
                    // Server error - add to retry queue
                    addToRetryQueue(allLogs)
                }
            }
        } catch {
            // Network or encoding error - add to retry queue
            addToRetryQueue(allLogs)
        }
    }

    // MARK: - Private Methods

    private func getRetryLogs() -> [LogEntry] {
        retryQueueLock.lock()
        defer { retryQueueLock.unlock() }
        return retryQueue
    }

    private func clearRetryLogs() {
        retryQueueLock.lock()
        defer { retryQueueLock.unlock() }
        retryQueue.removeAll()
    }

    private func addToRetryQueue(_ logs: [LogEntry]) {
        retryQueueLock.lock()
        defer { retryQueueLock.unlock() }

        // Add new logs to retry queue
        retryQueue = logs

        // Limit retry queue size to prevent unbounded growth
        let maxRetryLogs = 1000
        if retryQueue.count > maxRetryLogs {
            // Keep only the most recent logs
            retryQueue = Array(retryQueue.suffix(maxRetryLogs))
        }
    }
}
