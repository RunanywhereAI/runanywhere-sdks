import Foundation

/// SDK-wide constants (metadata only)
/// Capability-specific constants are in their respective capabilities:
/// - AnalyticsConstants (Analytics capability)
/// - LLMConstants (LLM capability)
/// - StorageConstants (FileManagement capability)
/// - DownloadConstants (Download capability)
/// - LifecycleConstants (Lifecycle capability)
/// - RegistryConstants (Registry capability)
public enum SDKConstants {
    /// SDK version - must match the VERSION file in the repository root
    /// Update this when bumping the SDK version
    public static let version = "0.16.0"

    /// SDK name
    public static let name = "RunAnywhere SDK"

    /// User agent string
    public static let userAgent = "\(name)/\(version) (Swift)"

    /// Platform identifier
    #if os(iOS)
    public static let platform = "ios"
    #elseif os(macOS)
    public static let platform = "macos"
    #elseif os(tvOS)
    public static let platform = "tvos"
    #elseif os(watchOS)
    public static let platform = "watchos"
    #else
    public static let platform = "unknown"
    #endif

    /// Minimum log level in production
    public static let productionLogLevel = "error"
}
