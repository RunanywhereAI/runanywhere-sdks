import Foundation

/// Registry and configuration management constants
public enum RegistryConstants {

    // MARK: - API Configuration

    /// Base API URLs for different environments
    public struct APIURLs {
        public let development: String
        public let staging: String
        public let production: String

        /// Get URL for current environment
        public var current: String {
            #if DEBUG
            return development
            #else
            return production
            #endif
        }
    }

    /// Default API URLs
    public static let apiURLs = APIURLs(
        development: loadConfig("api.development", default: "https://demo-api.example.com"),
        staging: loadConfig("api.staging", default: "https://demo-api.example.com"),
        production: loadConfig("api.production", default: "https://demo-api.example.com")
    )

    // MARK: - Feature Flags

    public struct Features {
        public let enableTelemetry: Bool
        public let enableDebugLogging: Bool
    }

    /// Default feature flags
    public static let features = Features(
        enableTelemetry: loadBool("features.telemetry", default: false),
        enableDebugLogging: loadBool("features.debugLogging", default: false)
    )

    // MARK: - SDK Configuration Defaults

    /// On-device only execution (default)
    public static let onDeviceOnly: Bool = true

    /// Analytics enabled by default
    public static let analyticsEnabled: Bool = true

    /// Enable live metrics for real-time tracking
    public static let enableLiveMetrics: Bool = true

    /// Default configuration ID
    public static let configurationId: String = "default"

    // MARK: - Platform Defaults

    /// Default supported platforms
    public static let defaultSupportedPlatforms = ["ios", "macos"]

    // MARK: - Configuration Loading

    private static func loadConfig(_ key: String, default defaultValue: String) -> String {
        // 1. Check environment variable
        let envKey = "RUNANYWHERE_\(key.uppercased().replacingOccurrences(of: ".", with: "_"))"
        if let envValue = ProcessInfo.processInfo.environment[envKey] {
            return envValue
        }

        // 2. Check JSON config file
        if let jsonValue = loadFromJSON(key: key) {
            return jsonValue
        }

        // 3. Return default (safe for GitHub)
        return defaultValue
    }

    private static func loadBool(_ key: String, default defaultValue: Bool) -> Bool {
        let stringValue = loadConfig(key, default: String(defaultValue))
        return stringValue.lowercased() == "true"
    }

    private static func loadFromJSON(key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "RunAnywhereConfig", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] // swiftlint:disable:this avoid_any_type
        else {
            return nil
        }

        // Navigate through nested keys (e.g., "api.production")
        let keyParts = key.split(separator: ".")
        var current: Any = json // swiftlint:disable:this avoid_any_type

        for part in keyParts {
            guard let dict = current as? [String: Any], // swiftlint:disable:this avoid_any_type
                  let value = dict[String(part)] else {
                return nil
            }
            current = value
        }

        return current as? String
    }
}
