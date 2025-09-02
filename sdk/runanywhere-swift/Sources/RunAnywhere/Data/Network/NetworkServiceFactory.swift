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
            logger.info("🔧 Creating MockNetworkService for DEVELOPMENT environment")
            logger.info("All network calls will return mock data without hitting real servers")
            return MockNetworkService()

        case .staging:
            guard let baseURL = params.baseURL else {
                logger.warning("⚠️ No baseURL provided for STAGING environment, using mock service")
                return MockNetworkService()
            }

            logger.info("🌐 Creating APIClient for STAGING environment")
            logger.info("Using staging server: \(baseURL.absoluteString)")

            // Staging uses real network but might have different configuration
            return APIClient(
                baseURL: baseURL,
                apiKey: params.apiKey
            )

        case .production:
            guard let baseURL = params.baseURL else {
                fatalError("❌ Production environment requires a valid baseURL")
            }

            logger.info("🚀 Creating APIClient for PRODUCTION environment")
            logger.info("Using production server: \(baseURL.absoluteString)")

            return APIClient(
                baseURL: baseURL,
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
    var shouldUseMockNetwork: Bool {
        switch self {
        case .development:
            return true
        case .staging, .production:
            return false
        }
    }

    /// Determine if the environment requires a base URL
    var requiresBaseURL: Bool {
        switch self {
        case .development:
            return false
        case .staging, .production:
            return true
        }
    }
}
