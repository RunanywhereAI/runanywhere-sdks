//
//  AnalyticsQueueManager.swift
//  RunAnywhere SDK
//
//  Centralized queue management for all analytics events with batching and retry
//

import Foundation

/// Central queue for all analytics - handles batching and retry logic
public actor AnalyticsQueueManager {

    // MARK: - Singleton

    public static let shared = AnalyticsQueueManager()

    // MARK: - Properties

    private var eventQueue: [any AnalyticsEvent] = []
    private let batchSize: Int = 50
    private let flushInterval: TimeInterval = 30.0
    private var telemetryRepository: (any TelemetryRepository)?
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

    public func initialize(telemetryRepository: any TelemetryRepository) {
        self.telemetryRepository = telemetryRepository
    }

    public func enqueue(_ event: any AnalyticsEvent) async {
        eventQueue.append(event)

        if eventQueue.count >= batchSize {
            await flushBatch()
        }
    }

    public func enqueueBatch(_ events: [any AnalyticsEvent]) async {
        eventQueue.append(contentsOf: events)

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

    private func processBatch(_ batch: [any AnalyticsEvent]) async {
        // For debugging: log analytics events locally if in debug mode
        #if DEBUG
        for event in batch {
            logger.debug("📊 Analytics Event: \(event.type)")
        }
        #endif

        guard let telemetryRepository = telemetryRepository else {
            logger.error("No telemetry repository configured")
            eventQueue.removeFirst(min(batch.count, eventQueue.count))
            return
        }

        // Convert to telemetry events
        let telemetryEvents = batch.compactMap { event -> TelemetryData? in
            do {
                let jsonData = try JSONEncoder().encode(event.eventData)
                let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

                return TelemetryData(
                    eventType: event.type,
                    properties: ["structured_data": jsonString],
                    timestamp: event.timestamp
                )
            } catch {
                logger.error("Failed to serialize event data for telemetry: \(error)")
                return nil
            }
        }

        // Send to backend via existing telemetry repository
        var success = false
        var attempt = 0

        while attempt < maxRetries && !success {
            do {
                // Send each event through telemetry repository
                for telemetryData in telemetryEvents {
                    if let eventType = TelemetryEventType(rawValue: telemetryData.eventType) {
                        try await telemetryRepository.trackEvent(eventType, properties: telemetryData.properties)
                    } else {
                        try await telemetryRepository.trackEvent(.custom, properties:
                            telemetryData.properties.merging(["event_type": telemetryData.eventType]) { _, new in new }
                        )
                    }
                }

                success = true
                eventQueue.removeFirst(min(batch.count, eventQueue.count))

            } catch {
                attempt += 1
                if attempt < maxRetries {
                    // Exponential backoff
                    let delay = pow(2.0, Double(attempt))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    logger.error("Failed to send batch after \(maxRetries) attempts")
                    eventQueue.removeFirst(min(batch.count, eventQueue.count))
                }
            }
        }
    }
}
