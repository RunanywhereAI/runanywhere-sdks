import Foundation

/// Simplified configuration for API network settings
public struct APIConfiguration: Codable, Sendable {
    /// Base URL for API requests
    public var baseURL: URL

    /// Timeout interval for requests (in seconds)
    public var timeoutInterval: TimeInterval

    public init(
        baseURL: URL = URL(string: RegistryConstants.apiURLs.current) ?? URL(fileURLWithPath: "/"),
        timeoutInterval: TimeInterval = 30.0
    ) {
        self.baseURL = baseURL
        self.timeoutInterval = timeoutInterval
    }
}
