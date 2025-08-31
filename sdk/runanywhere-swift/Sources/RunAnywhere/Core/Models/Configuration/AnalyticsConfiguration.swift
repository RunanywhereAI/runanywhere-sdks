import Foundation

/// Configuration for analytics and telemetry
public struct AnalyticsConfiguration: Codable, Sendable {
    /// Whether analytics is enabled
    public var enabled: Bool

    /// The level of analytics to collect
    public var level: AnalyticsLevel

    /// Whether live metrics are enabled
    public var liveMetricsEnabled: Bool

    /// Telemetry consent level
    public var telemetryConsent: TelemetryConsent

    /// Whether to include device information in analytics
    public var includeDeviceInfo: Bool

    /// Whether to include model information in analytics
    public var includeModelInfo: Bool

    /// Analytics batch size for remote submission
    public var batchSize: Int

    /// Analytics submission interval (seconds)
    public var submissionInterval: TimeInterval

    public init(
        enabled: Bool = true,
        level: AnalyticsLevel = .basic,
        liveMetricsEnabled: Bool = false,
        telemetryConsent: TelemetryConsent = .limited,
        includeDeviceInfo: Bool = true,
        includeModelInfo: Bool = true,
        batchSize: Int = 100,
        submissionInterval: TimeInterval = 300 // 5 minutes
    ) {
        self.enabled = enabled
        self.level = level
        self.liveMetricsEnabled = liveMetricsEnabled
        self.telemetryConsent = telemetryConsent
        self.includeDeviceInfo = includeDeviceInfo
        self.includeModelInfo = includeModelInfo
        self.batchSize = batchSize
        self.submissionInterval = submissionInterval
    }

    /// Whether any analytics should be collected
    public var shouldCollectAnalytics: Bool {
        enabled && level != .none
    }

    /// Whether performance metrics should be collected
    public var shouldCollectPerformanceMetrics: Bool {
        shouldCollectAnalytics && level.includesPerformanceMetrics
    }

    /// Whether memory metrics should be collected
    public var shouldCollectMemoryMetrics: Bool {
        shouldCollectAnalytics && level.includesMemoryTracking
    }

    /// Whether cost metrics should be collected
    public var shouldCollectCostMetrics: Bool {
        shouldCollectAnalytics && level.includesCostTracking
    }
}
