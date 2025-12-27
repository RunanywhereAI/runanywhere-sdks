import Foundation

/// Health status enum
public enum HealthStatus: String, Codable, Sendable {
    case healthy
    case degraded
    case unhealthy
}
