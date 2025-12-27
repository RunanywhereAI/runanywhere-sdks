import Foundation

/// Response model for health check
public struct HealthCheckResponse: Codable, Sendable {
    public let status: HealthStatus
    public let version: String
    public let timestamp: Date

    public init(status: HealthStatus, version: String, timestamp: Date) {
        self.status = status
        self.version = version
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case status
        case version
        case timestamp
    }
}
