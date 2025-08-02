import Foundation

/// Telemetry consent options
public enum TelemetryConsent: String, Codable {
    /// Full telemetry collection granted
    case granted

    /// Limited telemetry (errors only)
    case limited

    /// No telemetry collection
    case denied
}
