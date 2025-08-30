//
//  TelemetryService.swift
//  RunAnywhere SDK
//
//  Service layer for telemetry and analytics management
//

import Foundation

/// Service for managing telemetry data and analytics
public actor TelemetryService {
    private let logger = SDKLogger(category: "TelemetryService")
    private let telemetryRepository: any TelemetryRepository
    private let syncCoordinator: SyncCoordinator?

    // MARK: - Initialization

    public init(telemetryRepository: any TelemetryRepository, syncCoordinator: SyncCoordinator?) {
        self.telemetryRepository = telemetryRepository
        self.syncCoordinator = syncCoordinator
        logger.info("TelemetryService initialized")
    }

    // MARK: - Public Methods

    /// Track a telemetry event
    public func trackEvent(
        _ type: TelemetryEventType,
        properties: [String: String] = [:]
    ) async throws {
        try await telemetryRepository.trackEvent(type, properties: properties)
        logger.debug("Event tracked: \(type.rawValue)")
    }

    /// Track a custom event
    public func trackCustomEvent(
        _ name: String,
        properties: [String: String] = [:]
    ) async throws {
        let eventType = TelemetryEventType(rawValue: name) ?? .custom
        try await trackEvent(eventType, properties: properties)
    }

    /// Get all telemetry events
    public func getAllEvents() async throws -> [TelemetryData] {
        return try await telemetryRepository.fetchAll()
    }

    /// Get events within date range
    public func getEvents(from startDate: Date, to endDate: Date) async throws -> [TelemetryData] {
        return try await telemetryRepository.fetchByDateRange(from: startDate, to: endDate)
    }

    /// Get unsent events
    public func getUnsentEvents() async throws -> [TelemetryData] {
        return try await telemetryRepository.fetchUnsent()
    }

    /// Mark events as sent
    public func markEventsSent(_ eventIds: [String]) async throws {
        try await telemetryRepository.markAsSent(eventIds)
        logger.info("Marked \(eventIds.count) events as sent")
    }

    /// Clean up old events
    public func cleanupOldEvents(olderThan date: Date) async throws {
        try await telemetryRepository.cleanup(olderThan: date)
        logger.info("Cleaned up events older than \(date)")
    }

    /// Force sync telemetry data
    public func syncTelemetry() async throws {
        if let syncCoordinator = syncCoordinator,
           let repository = telemetryRepository as? TelemetryRepositoryImpl {
            try await syncCoordinator.sync(repository)
            logger.info("Telemetry sync triggered")
        }
    }

    // MARK: - Analytics Helpers

    /// Track SDK initialization
    public func trackInitialization(apiKey: String, version: String) async throws {
        try await trackEvent(.custom, properties: [
            "event": "initialized",
            "api_key_prefix": String(apiKey.prefix(8)),
            "sdk_version": version
        ])
    }

    /// Track model loading
    public func trackModelLoad(modelId: String, success: Bool, loadTime: TimeInterval) async throws {
        try await trackEvent(.modelLoaded, properties: [
            "model_id": modelId,
            "success": String(success),
            "load_time_ms": String(Int(loadTime * 1000))
        ])
    }

    /// Track generation
    public func trackGeneration(
        modelId: String,
        inputTokens: Int,
        outputTokens: Int,
        duration: TimeInterval
    ) async throws {
        try await trackEvent(.generationCompleted, properties: [
            "model_id": modelId,
            "input_tokens": String(inputTokens),
            "output_tokens": String(outputTokens),
            "duration_ms": String(Int(duration * 1000)),
            "tokens_per_second": String(Double(outputTokens) / duration)
        ])
    }

    /// Track error
    public func trackError(
        error: Error,
        context: String,
        additionalInfo: [String: String] = [:]
    ) async throws {
        var properties = additionalInfo
        properties["error"] = error.localizedDescription
        properties["context"] = context

        try await trackEvent(.error, properties: properties)
    }
}
