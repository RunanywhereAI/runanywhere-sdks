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
        guard !eventQueue.isEmpty else {
            return
        }

        let batch = Array(eventQueue.prefix(batchSize))
        await processBatch(batch)
    }

    private func processBatch(_ batch: [any AnalyticsEvent]) async {
        guard let telemetryRepository = telemetryRepository else {
            logger.warning("No telemetry repository configured - events will be dropped")
            eventQueue.removeFirst(min(batch.count, eventQueue.count))
            return
        }

        // Convert to telemetry events with full properties from event data
        let telemetryEvents = batch.compactMap { event -> TelemetryData? in
            // Extract properties from event data
            var properties: [String: String] = [:]

            // Use Mirror to extract all properties from eventData
            let mirror = Mirror(reflecting: event.eventData)
            for child in mirror.children {
                if let label = child.label {
                    // Convert value to string representation
                    let value: String
                    if let stringValue = child.value as? String {
                        value = stringValue
                    } else if let intValue = child.value as? Int {
                        value = String(intValue)
                    } else if let doubleValue = child.value as? Double {
                        value = String(format: "%.3f", doubleValue)
                    } else if let floatValue = child.value as? Float {
                        value = String(format: "%.3f", floatValue)
                    } else if let boolValue = child.value as? Bool {
                        value = String(boolValue)
                    } else if let int64Value = child.value as? Int64 {
                        value = String(int64Value)
                    } else {
                        value = String(describing: child.value)
                    }
                    // Convert camelCase to snake_case for backend
                    let snakeKey = label.camelCaseToSnakeCase()
                    properties[snakeKey] = value
                }
            }

            return TelemetryData(
                eventType: event.type,
                properties: properties,
                timestamp: event.timestamp
            )
        }

        // Store locally first, then send to backend
        var success = false
        var attempt = 0

        while attempt < maxRetries && !success {
            do {
                // Store each event locally
                for telemetryData in telemetryEvents {
                    if let eventType = TelemetryEventType(rawValue: telemetryData.eventType) {
                        try await telemetryRepository.trackEvent(eventType, properties: telemetryData.properties)
                    } else {
                        try await telemetryRepository.trackEvent(.custom, properties:
                            telemetryData.properties.merging(["event_type": telemetryData.eventType]) { _, new in new }
                        )
                    }
                }

                // Now sync to backend via remote data source
                if let remoteDataSource = telemetryRepository.remoteDataSource {
                    try await remoteDataSource.sendBatch(telemetryEvents)
                }

                success = true
                eventQueue.removeFirst(min(batch.count, eventQueue.count))

            } catch {
                attempt += 1
                logger.error("Failed to process batch (attempt \(attempt)/\(maxRetries)): \(error)")
                if attempt < maxRetries {
                    // Exponential backoff
                    let delay = pow(2.0, Double(attempt))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    logger.error("Failed to send batch after \(maxRetries) attempts, events stored locally for later sync")
                    eventQueue.removeFirst(min(batch.count, eventQueue.count))
                }
            }
        }
    }
}

// MARK: - String Extension for camelCase to snake_case

private extension String {
    func camelCaseToSnakeCase() -> String {
        let pattern = "([a-z0-9])([A-Z])"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: self.count)
        return regex?.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: "$1_$2").lowercased() ?? self.lowercased()
    }
}
