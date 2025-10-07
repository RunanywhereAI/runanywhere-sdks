import Foundation

/// SDK Configuration
public struct Configuration {
    /// API key for authentication
    public let apiKey: String

    /// Base URL for API requests
    public var baseURL: URL

    /// Enable real-time dashboard updates
    public var enableRealTimeDashboard: Bool

    /// Routing policy for model selection
    public var routingPolicy: RoutingPolicy

    /// Telemetry consent
    public var telemetryConsent: TelemetryConsent

    /// Privacy mode settings
    public var privacyMode: PrivacyMode

    /// Debug mode flag
    public var debugMode: Bool

    /// Preferred frameworks for model execution
    public var preferredFrameworks: [LLMFramework]

    /// Hardware preferences for model execution
    public var hardwarePreferences: HardwareConfiguration?

    /// Model provider configurations
    public var modelProviders: [ModelProviderConfig]

    /// Memory threshold for model loading (in bytes)
    public var memoryThreshold: Int64

    /// Download configuration
    public var downloadConfiguration: DownloadConfig

    /// Default generation settings
    public var defaultGenerationSettings: DefaultGenerationSettings

    /// Initialize configuration with API key
    /// - Parameters:
    ///   - apiKey: Your RunAnywhere API key
    ///   - enableRealTimeDashboard: Enable real-time cost tracking dashboard (default: true)
    ///   - telemetryConsent: Telemetry consent preference (default: .granted)
    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.runanywhere.ai") ?? URL(fileURLWithPath: "/"),
        enableRealTimeDashboard: Bool = true,
        telemetryConsent: TelemetryConsent = .granted
    ) {
        self.apiKey = apiKey
        self.baseURL = URL(string: "https://api.runanywhere.ai") ?? URL(fileURLWithPath: "/")
        self.enableRealTimeDashboard = enableRealTimeDashboard
        self.routingPolicy = .deviceOnly  // FORCE DEVICE-ONLY ROUTING - NEVER USE CLOUD
        self.telemetryConsent = telemetryConsent
        self.privacyMode = .standard
        self.debugMode = false
        self.preferredFrameworks = []
        self.hardwarePreferences = nil
        self.modelProviders = []
        self.memoryThreshold = 500_000_000 // 500MB default
        self.downloadConfiguration = DownloadConfig()
        self.defaultGenerationSettings = DefaultGenerationSettings()
    }
}
