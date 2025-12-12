import Foundation

/// Protocol for configuration services
public protocol ConfigurationServiceProtocol: Actor {
    func getConfiguration() -> ConfigurationData?
    func ensureConfigurationLoaded() async
    func updateConfiguration(_ updates: (ConfigurationData) -> ConfigurationData) async
    func syncToCloud() async throws

    // Simple configuration methods
    func loadConfigurationOnLaunch(apiKey: String) async -> ConfigurationData
    func setConsumerConfiguration(_ config: ConfigurationData) async throws
}
