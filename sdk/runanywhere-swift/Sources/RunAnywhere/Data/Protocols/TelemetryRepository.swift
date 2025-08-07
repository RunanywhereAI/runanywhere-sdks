import Foundation

/// Repository protocol for telemetry data persistence
public protocol TelemetryRepository: Repository where Entity == TelemetryData {
    // Telemetry-specific operations
    func fetchByDateRange(from: Date, to: Date) async throws -> [TelemetryData]
    func fetchUnsent() async throws -> [TelemetryData]
    func markAsSent(_ ids: [String]) async throws
    func cleanup(olderThan date: Date) async throws

    // Additional methods
    func trackEvent(_ type: TelemetryEventType, properties: [String: String]) async throws
}
