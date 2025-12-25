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

    public func initialize(telemetryRepository: TelemetryRepositoryImpl) async {
        self.telemetryRepository = telemetryRepository

        // Verify remote data source is available
        let hasRemote = await telemetryRepository.remoteDataSource != nil
        if !hasRemote {
            logger.error("TelemetryRepository has no remoteDataSource - events will NOT be sent to backend")
        }
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
        guard !eventQueue.isEmpty else {
            return
        }

        guard telemetryRepository != nil else {
            return
        }

        let batch = Array(eventQueue.prefix(batchSize))
        await processBatch(batch)
    }

    private func processBatch(_ batch: [any SDKEvent]) async {
        guard let telemetryRepository = telemetryRepository else {
            eventQueue.removeFirst(min(batch.count, eventQueue.count))
            return
        }

        // Get device info for enrichment
        let deviceInfo = DeviceInfo.current
        let deviceMetadata: [String: String] = [
            "device": deviceInfo.deviceModel,
            "device_model": deviceInfo.deviceModel,
            "os_version": deviceInfo.osVersion,
            "platform": deviceInfo.platform,
            "sdk_version": SDKConstants.version
        ]

        // Create TelemetryEventPayload directly from SDKEvent (preserves category → modality!)
        let payloads: [TelemetryEventPayload] = batch.map { event in
            if let typedEvent = event as? (any TypedEventProperties) {
                return TelemetryEventPayload(from: event, typedProperties: typedEvent.typedProperties)
            } else {
                return TelemetryEventPayload(from: event) // Uses event.category directly!
            }
        }

        var success = false
        var attempt = 0

        while attempt < maxRetries && !success {
            do {
                // Try to store events locally (optional - skip if database not available)
                do {
                    for event in batch {
                        let enrichedProperties = event.properties.merging(deviceMetadata) { eventValue, _ in eventValue }
                        if let eventType = TelemetryEventType(rawValue: event.type) {
                            try await telemetryRepository.trackEvent(eventType, properties: enrichedProperties)
                        } else {
                            try await telemetryRepository.trackEvent(
                                .custom,
                                properties: enrichedProperties.merging(
                                    ["event_type": event.type]
                                ) { _, new in new }
                            )
                        }
                    }
                } catch {
                    // Database not available - skip local storage, continue to remote
                }

                // Sync to backend using typed payloads (preserves category → modality)
                if let remoteDataSource = telemetryRepository.remoteDataSource {
                    try await remoteDataSource.sendPayloads(payloads)
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
