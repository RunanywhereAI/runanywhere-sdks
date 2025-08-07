import Foundation

/// Repository protocol for configuration data persistence
public protocol ConfigurationRepository: Repository where Entity == ConfigurationData {
    // Additional configuration-specific methods if needed
    func fetchByKey(_ key: String) async throws -> ConfigurationData?
    func updatePartial(_ id: String, updates: (ConfigurationData) -> ConfigurationData) async throws
}
