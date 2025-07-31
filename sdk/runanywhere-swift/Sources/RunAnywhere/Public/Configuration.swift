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
    
    /// Initialize configuration with API key
    /// - Parameters:
    ///   - apiKey: Your RunAnywhere API key
    ///   - enableRealTimeDashboard: Enable real-time cost tracking dashboard (default: true)
    ///   - telemetryConsent: Telemetry consent preference (default: .granted)
    public init(
        apiKey: String,
        enableRealTimeDashboard: Bool = true,
        telemetryConsent: TelemetryConsent = .granted
    ) {
        self.apiKey = apiKey
        self.baseURL = URL(string: "https://api.runanywhere.ai") ?? URL(fileURLWithPath: "/")
        self.enableRealTimeDashboard = enableRealTimeDashboard
        self.routingPolicy = .automatic
        self.telemetryConsent = telemetryConsent
        self.privacyMode = .standard
        self.debugMode = false
        self.preferredFrameworks = []
        self.hardwarePreferences = nil
        self.modelProviders = []
        self.memoryThreshold = 500_000_000 // 500MB default
        self.downloadConfiguration = DownloadConfig()
    }
}

/// Routing policy determines how requests are routed between device and cloud
public enum RoutingPolicy: String, Codable {
    /// Automatically determine best execution target
    case automatic
    
    /// Always use on-device execution when possible
    case preferDevice
    
    /// Always use cloud execution
    case preferCloud
    
    /// Use custom routing rules
    case custom
}

/// Telemetry consent options
public enum TelemetryConsent: String, Codable {
    /// Full telemetry collection granted
    case granted
    
    /// Limited telemetry (errors only)
    case limited
    
    /// No telemetry collection
    case denied
}

/// Privacy mode settings
public enum PrivacyMode: String, Codable {
    /// Standard privacy protection
    case standard
    
    /// Enhanced privacy with stricter PII detection
    case strict
    
    /// Custom privacy rules
    case custom
}

/// Execution target for model inference
public enum ExecutionTarget: String, Codable {
    /// Execute on device
    case onDevice
    
    /// Execute in the cloud
    case cloud
    
    /// Hybrid execution (partial on-device, partial cloud)
    case hybrid
}

/// Context for maintaining conversation state
public struct Context: Codable {
    /// Previous messages in the conversation
    public let messages: [Message]
    
    /// System prompt override
    public let systemPrompt: String?
    
    /// Maximum context window size
    public let maxTokens: Int
    
    public init(
        messages: [Message] = [],
        systemPrompt: String? = nil,
        maxTokens: Int = 2048
    ) {
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.maxTokens = maxTokens
    }
}

/// Message in a conversation
public struct Message: Codable {
    /// Role of the message sender
    public let role: Role
    
    /// Content of the message
    public let content: String
    
    /// Timestamp
    public let timestamp: Date
    
    public enum Role: String, Codable {
        case user
        case assistant
        case system
    }
    
    public init(role: Role, content: String, timestamp: Date = Date()) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

/// Model provider configuration
public struct ModelProviderConfig {
    /// Provider name (e.g., "HuggingFace", "Kaggle")
    public let provider: String
    
    /// Authentication credentials
    public let credentials: ProviderCredentials?
    
    /// Whether this provider is enabled
    public let enabled: Bool
    
    public init(
        provider: String,
        credentials: ProviderCredentials? = nil,
        enabled: Bool = true
    ) {
        self.provider = provider
        self.credentials = credentials
        self.enabled = enabled
    }
}

/// Download configuration
public struct DownloadConfig {
    /// Maximum concurrent downloads
    public let maxConcurrentDownloads: Int
    
    /// Number of retry attempts
    public let retryAttempts: Int
    
    /// Custom cache directory
    public let cacheDirectory: URL?
    
    /// Download timeout in seconds
    public let timeoutInterval: TimeInterval
    
    public init(
        maxConcurrentDownloads: Int = 2,
        retryAttempts: Int = 3,
        cacheDirectory: URL? = nil,
        timeoutInterval: TimeInterval = 300
    ) {
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.retryAttempts = retryAttempts
        self.cacheDirectory = cacheDirectory
        self.timeoutInterval = timeoutInterval
    }
}
