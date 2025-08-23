import Foundation

/// Simple configuration class to control analytics logging
public class AnalyticsLoggingConfig {
    public static let shared = AnalyticsLoggingConfig()

    /// Whether analytics logging is enabled
    public var logToLocal: Bool = false

    private init() {}
}
