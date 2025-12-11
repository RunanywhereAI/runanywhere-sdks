//
//  TelemetryRepository.swift
//  RunAnywhere SDK
//
//  Repository protocol for telemetry data persistence
//

import Foundation

/// Repository protocol for telemetry data persistence
/// Defines operations for storing, retrieving, and syncing telemetry events
public protocol TelemetryRepository: Repository where Entity == TelemetryData {

    // MARK: - Query Operations

    /// Fetch telemetry events within a date range
    /// - Parameters:
    ///   - from: Start date
    ///   - to: End date
    /// - Returns: Array of telemetry events within the range
    func fetchByDateRange(from: Date, to: Date) async throws -> [TelemetryData]

    /// Fetch telemetry events that haven't been synced to remote
    /// - Returns: Array of unsent telemetry events
    func fetchUnsent() async throws -> [TelemetryData]

    // MARK: - Sync Operations

    /// Mark telemetry events as sent/synced
    /// - Parameter ids: Array of event IDs to mark as sent
    func markAsSent(_ ids: [String]) async throws

    // MARK: - Maintenance

    /// Clean up telemetry events older than specified date
    /// - Parameter date: Date threshold for cleanup
    func cleanup(olderThan date: Date) async throws

    // MARK: - Event Tracking

    /// Track a new telemetry event
    /// - Parameters:
    ///   - type: Type of telemetry event
    ///   - properties: Additional properties for the event
    func trackEvent(_ type: TelemetryEventType, properties: [String: String]) async throws
}
