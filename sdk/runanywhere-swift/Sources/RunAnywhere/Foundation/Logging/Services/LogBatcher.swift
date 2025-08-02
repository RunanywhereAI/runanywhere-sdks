//
//  LogBatcher.swift
//  RunAnywhere SDK
//
//  Batches log entries for efficient remote submission
//

import Foundation

/// Manages batching of log entries for remote submission
internal class LogBatcher {

    // MARK: - Properties

    /// Log entries pending submission
    private var pendingLogs: [LogEntry] = []

    /// Serial queue for thread-safe access
    private let queue = DispatchQueue(label: "com.runanywhere.sdk.logging.batcher", qos: .utility)

    /// Configuration for batching behavior
    private let configuration: LoggingConfiguration

    /// Timer for periodic batch submission
    private var batchTimer: Timer?

    /// Callback for when a batch is ready
    private let onBatchReady: ([LogEntry]) -> Void

    // MARK: - Initialization

    init(configuration: LoggingConfiguration, onBatchReady: @escaping ([LogEntry]) -> Void) {
        self.configuration = configuration
        self.onBatchReady = onBatchReady
        startBatchTimer()
    }

    deinit {
        stopBatchTimer()
    }

    // MARK: - Public Methods

    /// Add a log entry to the batch
    func add(_ entry: LogEntry) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.pendingLogs.append(entry)

            if self.pendingLogs.count >= self.configuration.batchSize {
                self.flushBatch()
            }
        }
    }

    /// Force flush all pending logs
    func flush() {
        queue.async { [weak self] in
            self?.flushBatch()
        }
    }

    /// Update configuration and restart timer if needed
    func updateConfiguration(_ newConfig: LoggingConfiguration) {
        queue.async { [weak self] in
            self?.stopBatchTimer()
            if newConfig.enableRemoteLogging {
                self?.startBatchTimer()
            }
        }
    }

    // MARK: - Private Methods

    private func flushBatch() {
        guard !pendingLogs.isEmpty else { return }

        let logsToSend = pendingLogs
        pendingLogs.removeAll()

        // Call the batch ready handler
        onBatchReady(logsToSend)
    }

    private func startBatchTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.batchTimer = Timer.scheduledTimer(
                withTimeInterval: self.configuration.batchInterval,
                repeats: true
            ) { [weak self] _ in
                self?.flush()
            }
        }
    }

    private func stopBatchTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.batchTimer?.invalidate()
            self?.batchTimer = nil
        }
    }
}
