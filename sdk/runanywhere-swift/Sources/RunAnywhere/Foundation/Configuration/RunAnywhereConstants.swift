import Foundation

/// Simple constants configuration for the SDK
public enum RunAnywhereConstants {

    // MARK: - API Configuration

    /// Base API URLs for different environments
    public static let apiURLs = APIURLs(
        development: loadConfig("api.development", default: "https://demo-api.example.com"),
        staging: loadConfig("api.staging", default: "https://demo-api.example.com"),
        production: loadConfig("api.production", default: "https://demo-api.example.com")
    )


    // MARK: - Feature Flags

    public static let features = Features(
        enableTelemetry: loadBool("features.telemetry", default: false),
        enableDebugLogging: loadBool("features.debugLogging", default: false)
    )

    // MARK: - Types

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

    public struct Features {
        public let enableTelemetry: Bool
        public let enableDebugLogging: Bool
    }

    // MARK: - Configuration Loading

    private static func loadConfig(_ key: String, default defaultValue: String) -> String {
        // 1. Check environment variable
        if let envValue = ProcessInfo.processInfo.environment["RUNANYWHERE_\(key.uppercased().replacingOccurrences(of: ".", with: "_"))"] {
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
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Navigate through nested keys (e.g., "api.production")
        let keyParts = key.split(separator: ".")
        var current: Any = json

        for part in keyParts {
            guard let dict = current as? [String: Any],
                  let value = dict[String(part)] else {
                return nil
            }
            current = value
        }

        return current as? String
    }

}
