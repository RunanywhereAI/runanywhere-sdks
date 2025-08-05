import Foundation

/// Protocol for managing SDK configuration with multi-tier support
public protocol ConfigurationManager: Actor {
    /// Get current generation settings
    func getGenerationSettings() -> DefaultGenerationSettings

    /// Update generation settings from remote configuration
    func updateRemoteSettings(_ settings: [String: Any]) async

    /// Set user override for temperature
    func setTemperature(_ value: Float)

    /// Set user override for max tokens
    func setMaxTokens(_ value: Int)

    /// Set user override for top-p
    func setTopP(_ value: Float)

    /// Set user override for top-k
    func setTopK(_ value: Int)

    /// Clear all user overrides
    func clearUserOverrides()

    /// Check if user overrides are allowed
    var allowUserOverride: Bool { get }

    /// Sync user preferences to remote server
    func syncUserPreferences() async throws

    /// Register callback for settings changes
    func onSettingsChanged(_ callback: @escaping (DefaultGenerationSettings) -> Void)
}
