import Foundation

/// Analytics and telemetry configuration constants
public enum AnalyticsConstants {

    // MARK: - Telemetry Defaults

    /// Batch size for telemetry sync
    public static let telemetryBatchSize = 50

    /// Telemetry consent levels
    public enum ConsentLevel: String {
        case none = "none"
        case anonymous = "anonymous"
        case detailed = "detailed"
    }

    // MARK: - Analytics Defaults

    /// Analytics levels
    public enum Level: String {
        case basic = "basic"
        case detailed = "detailed"
        case debug = "debug"
    }

    /// Default analytics level
    public static let defaultLevel: Level = .basic
}
