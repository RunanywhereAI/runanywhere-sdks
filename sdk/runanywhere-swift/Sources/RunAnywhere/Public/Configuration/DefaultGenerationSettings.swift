import Foundation

/// Default generation settings that can be configured at SDK level
public struct DefaultGenerationSettings: Codable {
    /// Default temperature for sampling
    public var temperature: Float

    /// Default maximum tokens
    public var maxTokens: Int

    /// Default top-p sampling parameter
    public var topP: Float

    /// Default top-k sampling parameter
    public var topK: Int

    /// Whether these settings can be overridden by users
    public var allowUserOverride: Bool

    /// Initialize with default values
    public init(
        temperature: Float = 0.7,
        maxTokens: Int = 150,
        topP: Float = 0.95,
        topK: Int = 40,
        allowUserOverride: Bool = true
    ) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
        self.topK = topK
        self.allowUserOverride = allowUserOverride
    }

    /// Create from remote configuration
    public static func from(remoteConfig: [String: Any]) -> DefaultGenerationSettings? {
        guard let data = try? JSONSerialization.data(withJSONObject: remoteConfig),
              let settings = try? JSONDecoder().decode(DefaultGenerationSettings.self, from: data) else {
            return nil
        }
        return settings
    }
}
