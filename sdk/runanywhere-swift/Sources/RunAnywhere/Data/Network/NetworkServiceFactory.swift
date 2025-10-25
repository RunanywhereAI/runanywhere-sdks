import Foundation

/// Factory for creating the appropriate network service based on environment
/// This provides a CLEAN separation between mock and real network implementations
public enum NetworkServiceFactory {

    /// Create a network service based on the environment
    /// - Parameters:
    ///   - environment: The SDK environment (development/staging/production)
    ///   - params: SDK initialization parameters
    /// - Returns: A NetworkService implementation appropriate for the environment
    public static func createNetworkService(
        for environment: SDKEnvironment,
        params: SDKInitParams
    ) -> any NetworkService {

        let logger = SDKLogger(category: "NetworkServiceFactory")

        switch environment {
        case .development:
            logger.info("🔧 Creating APIClient for DEVELOPMENT environment")
            logger.info("Using development server: \(params.baseURL.absoluteString)")
            logger.info("⚠️ Development mode will still make real network calls for device registration")

            return APIClient(
                baseURL: params.baseURL,
                apiKey: params.apiKey
            )

        case .staging:
            logger.info("🌐 Creating APIClient for STAGING environment")
            logger.info("Using staging server: \(params.baseURL.absoluteString)")

            // Staging uses real network but might have different configuration
            return APIClient(
                baseURL: params.baseURL,
                apiKey: params.apiKey
            )

        case .production:
            logger.info("🚀 Creating APIClient for PRODUCTION environment")
            logger.info("Using production server: \(params.baseURL.absoluteString)")

            return APIClient(
                baseURL: params.baseURL,
                apiKey: params.apiKey
            )
        }
    }

    /// Create a network service with custom configuration
    /// - Parameters:
    ///   - useMocks: Force use of mock service regardless of environment
    ///   - baseURL: Base URL for real network calls
    ///   - apiKey: API key for authentication
    /// - Returns: A NetworkService implementation
    public static func createCustomNetworkService(
        useMocks: Bool,
        baseURL: URL?,
        apiKey: String
    ) -> any NetworkService {

        let logger = SDKLogger(category: "NetworkServiceFactory")

        if useMocks {
            logger.info("🔧 Creating MockNetworkService (custom configuration)")
            return MockNetworkService()
        } else {
            guard let baseURL = baseURL else {
                logger.warning("⚠️ No baseURL provided, falling back to mock service")
                return MockNetworkService()
            }

            logger.info("🌐 Creating APIClient (custom configuration)")
            return APIClient(
                baseURL: baseURL,
                apiKey: apiKey
            )
        }
    }
}

/// Extension to help determine if mocks should be used
public extension SDKEnvironment {
    /// Determine if network mocks should be used for this environment
    /// Note: Development mode now uses real network calls for device registration
    var shouldUseMockNetwork: Bool {
        switch self {
        case .development:
            return false // Changed: development now uses real network calls
        case .staging, .production:
            return false
        }
    }

    /// Determine if the environment requires a base URL
    var requiresBaseURL: Bool {
        switch self {
        case .development:
            return true // Changed: development now requires baseURL for real network calls
        case .staging, .production:
            return true
        }
    }
}
