import CRACommons

/// SDK-wide constants (metadata only)
/// Capability-specific constants are in their respective capabilities:
/// - LLMConstants (LLM capability)
/// - StorageConstants (FileManagement capability)
/// - DownloadConstants (Download capability)
/// - LifecycleConstants (Lifecycle capability)
/// - RegistryConstants (Registry capability)
public enum SDKConstants {
    /// SDK version. Single source of truth is `sdk/runanywhere-commons/VERSION`,
    /// exposed through `rac_sdk_get_version()`, so the value reported here can
    /// never drift from the version commons reports in telemetry / auth headers.
    public static let version = String(cString: rac_sdk_get_version())

    /// SDK name
    public static let name = "RunAnywhere SDK"

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
