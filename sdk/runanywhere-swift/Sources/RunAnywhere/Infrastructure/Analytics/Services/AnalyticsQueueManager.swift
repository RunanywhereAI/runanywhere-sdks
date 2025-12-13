//
//  AnalyticsQueueManager.swift
//  RunAnywhere SDK
//
//  Centralized queue management for analytics events with batching and retry.
//

import Foundation

// MARK: - Analytics Queue Manager

/// Central queue for all analytics events.
/// Handles batching, local persistence, and backend sync.
public actor AnalyticsQueueManager {

    // MARK: - Singleton

    public static let shared = AnalyticsQueueManager()

    // MARK: - Properties

    private var eventQueue: [any SDKEvent] = []
    private let batchSize: Int = 50
    private let flushInterval: TimeInterval = 30.0
    private var telemetryRepository: TelemetryRepositoryImpl?
    private let logger = SDKLogger(category: "AnalyticsQueue")
    private var flushTask: Task<Void, Never>?
    private let maxRetries = 3

    // MARK: - Initialization

    private init() {
        Task {
            await startFlushTimer()
        }
    }

    deinit {
        flushTask?.cancel()
    }

    // MARK: - Public Methods

    public func initialize(telemetryRepository: TelemetryRepositoryImpl) {
        self.telemetryRepository = telemetryRepository
    }

    /// Enqueue an event for analytics processing
    public func enqueue(_ event: any SDKEvent) async {
        eventQueue.append(event)

        if eventQueue.count >= batchSize {
            await flushBatch()
        }
    }

    /// Force flush all pending events
    public func flush() async {
        await flushBatch()
    }

    // MARK: - Private Methods

    private func startFlushTimer() {
        flushTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(flushInterval * 1_000_000_000))
                await flushBatch()
            }
        }
    }

    private func flushBatch() async {
        guard !eventQueue.isEmpty else { return }

        let batch = Array(eventQueue.prefix(batchSize))
        await processBatch(batch)
    }

    private func processBatch(_ batch: [any SDKEvent]) async {
        guard let telemetryRepository = telemetryRepository else {
            logger.warning("No telemetry repository configured - events will be dropped")
            eventQueue.removeFirst(min(batch.count, eventQueue.count))
            return
        }

        // Convert SDKEvent to TelemetryData
        let telemetryEvents = batch.map { event in
            TelemetryData(
                eventType: event.type,
                properties: event.properties,
                timestamp: event.timestamp
            )
        }

        var success = false
        var attempt = 0

        while attempt < maxRetries && !success {
            do {
                // Store each event locally
                for telemetryData in telemetryEvents {
                    if let eventType = TelemetryEventType(rawValue: telemetryData.eventType) {
                        try await telemetryRepository.trackEvent(eventType, properties: telemetryData.properties)
                    } else {
                        try await telemetryRepository.trackEvent(
                            .custom,
                            properties: telemetryData.properties.merging(
                                ["event_type": telemetryData.eventType]
                            ) { _, new in new }
                        )
                    }
                }

                // Sync to backend
                if let remoteDataSource = telemetryRepository.remoteDataSource {
                    try await remoteDataSource.sendBatch(telemetryEvents)
                }

                success = true
                eventQueue.removeFirst(min(batch.count, eventQueue.count))

            } catch {
                attempt += 1
                logger.warning("Failed to process batch (attempt \(attempt)/\(maxRetries)): \(error)")
                if attempt < maxRetries {
                    let delay = pow(2.0, Double(attempt))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    logger.error("Failed to send batch after \(maxRetries) attempts, stored locally")
                    eventQueue.removeFirst(min(batch.count, eventQueue.count))
                }
            }
        }
    }
}
