import Foundation

/// Configuration for telemetry and analytics
public struct TelemetryConfiguration: Codable, Sendable {
    /// Telemetry consent level
    public var consent: TelemetryConsent

    /// Enable real-time dashboard updates
    public var enableRealTimeDashboard: Bool

    /// Enable performance tracking
    public var enablePerformanceTracking: Bool

    /// Enable error reporting
    public var enableErrorReporting: Bool

    /// Batch size for analytics events
    public var analyticsBatchSize: Int

    /// Flush interval for analytics (seconds)
    public var analyticsFlushInterval: TimeInterval

    public init(
        consent: TelemetryConsent = .granted,
        enableRealTimeDashboard: Bool = true,
        enablePerformanceTracking: Bool = true,
        enableErrorReporting: Bool = true,
        analyticsBatchSize: Int = 50,
        analyticsFlushInterval: TimeInterval = 30.0
    ) {
        self.consent = consent
        self.enableRealTimeDashboard = enableRealTimeDashboard
        self.enablePerformanceTracking = enablePerformanceTracking
        self.enableErrorReporting = enableErrorReporting
        self.analyticsBatchSize = analyticsBatchSize
        self.analyticsFlushInterval = analyticsFlushInterval
    }
}
