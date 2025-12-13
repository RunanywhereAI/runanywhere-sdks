import Foundation

/// Configuration-specific repository methods
/// ConfigurationRepositoryImpl will implement both this AND Repository<ConfigurationData>
public protocol ConfigurationRepository {
    // Configuration-specific operations
    func fetchRemoteConfiguration(apiKey: String) async throws -> ConfigurationData?
    func setConsumerConfiguration(_ config: ConfigurationData) async throws
    func getConsumerConfiguration() async throws -> ConfigurationData?
    func getSDKDefaultConfiguration() -> ConfigurationData
}
