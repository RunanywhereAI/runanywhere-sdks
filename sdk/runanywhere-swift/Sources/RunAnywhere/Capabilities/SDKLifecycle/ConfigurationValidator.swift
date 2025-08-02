import Foundation

/// Validates SDK configuration
public class ConfigurationValidator {

    public init() {}

    /// Validate the provided configuration
    /// - Parameter configuration: The configuration to validate
    /// - Throws: SDKError if configuration is invalid
    public func validate(_ configuration: Configuration) async throws {
        // Validate API key
        if configuration.apiKey.isEmpty {
            throw SDKError.validationFailed(
                ValidationError.invalidMetadata(reason: "API key cannot be empty")
            )
        }

        // Validate base URL
        if configuration.baseURL.absoluteString.isEmpty {
            throw SDKError.validationFailed(
                ValidationError.invalidMetadata(reason: "Base URL is invalid")
            )
        }

        // Validate memory threshold
        if configuration.memoryThreshold < 100_000_000 { // 100MB minimum
            throw SDKError.validationFailed(
                ValidationError.invalidMetadata(
                    reason: "Memory threshold must be at least 100MB"
                )
            )
        }

        // Validate download configuration
        let downloadConfig = configuration.downloadConfiguration
        if downloadConfig.maxConcurrentDownloads < 1 {
            throw SDKError.validationFailed(
                ValidationError.invalidMetadata(
                    reason: "Max concurrent downloads must be at least 1"
                )
            )
        }

        if downloadConfig.retryAttempts < 0 {
            throw SDKError.validationFailed(
                ValidationError.invalidMetadata(
                    reason: "Retry attempts cannot be negative"
                )
            )
        }

        if downloadConfig.timeoutInterval < 10 {
            throw SDKError.validationFailed(
                ValidationError.invalidMetadata(
                    reason: "Timeout interval must be at least 10 seconds"
                )
            )
        }

        // Validate model providers
        for provider in configuration.modelProviders {
            if provider.provider.isEmpty {
                throw SDKError.validationFailed(
                    ValidationError.invalidMetadata(
                        reason: "Model provider name cannot be empty"
                    )
                )
            }
        }
    }
}
