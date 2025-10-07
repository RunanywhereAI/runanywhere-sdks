import Foundation

/// Model provider configuration
public struct ModelProviderConfig {
    /// Provider name (e.g., "HuggingFace", "Kaggle")
    public let provider: String

    /// Authentication credentials
    public let credentials: ProviderCredentials?

    /// Whether this provider is enabled
    public let enabled: Bool

    public init(
        provider: String,
        credentials: ProviderCredentials? = nil,
        enabled: Bool = true
    ) {
        self.provider = provider
        self.credentials = credentials
        self.enabled = enabled
    }
}
