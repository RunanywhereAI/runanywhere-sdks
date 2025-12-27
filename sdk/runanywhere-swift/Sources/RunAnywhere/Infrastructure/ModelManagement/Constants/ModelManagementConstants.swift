import Foundation

/// Lifecycle and model management configuration constants
public enum LifecycleConstants {

    // MARK: - SDK Configuration

    /// SDK version - references the single source of truth
    public static var sdkVersion: String { SDKConstants.version }

    /// Default model version
    public static let modelVersion = "1.0"

    // MARK: - Model Defaults

    /// Default model cache size
    public static let defaultModelCacheSize = 5
}
