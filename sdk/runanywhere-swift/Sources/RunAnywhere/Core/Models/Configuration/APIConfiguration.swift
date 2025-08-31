import Foundation

/// Configuration for API endpoints and network settings
public struct APIConfiguration: Codable, Sendable {
    /// Base URL for API requests
    public var baseURL: URL

    /// Timeout interval for requests
    public var timeoutInterval: TimeInterval

    /// Maximum retry attempts
    public var maxRetries: Int

    /// Custom headers to include with requests
    public var customHeaders: [String: String]?

    public init(
        baseURL: URL = URL(string: RunAnywhereConstants.apiURLs.current) ?? URL(fileURLWithPath: "/"),
        timeoutInterval: TimeInterval = 30.0,
        maxRetries: Int = 3,
        customHeaders: [String: String]? = nil
    ) {
        self.baseURL = baseURL
        self.timeoutInterval = timeoutInterval
        self.maxRetries = maxRetries
        self.customHeaders = customHeaders
    }
}
