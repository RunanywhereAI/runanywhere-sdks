import Foundation

/// Protocol for authentication providers
public protocol AuthProvider {
    /// Provider name
    var providerName: String { get }

    /// Check if credentials are stored
    /// - Returns: Whether valid credentials exist
    func hasStoredCredentials() -> Bool

    /// Store credentials securely
    /// - Parameter credentials: Credentials to store
    func storeCredentials(_ credentials: ProviderCredentials) async throws

    /// Retrieve stored credentials
    /// - Returns: Stored credentials if available
    func retrieveCredentials() async throws -> ProviderCredentials?

    /// Remove stored credentials
    func removeCredentials() async throws

    /// Validate credentials
    /// - Parameter credentials: Credentials to validate
    /// - Returns: Whether credentials are valid
    func validateCredentials(_ credentials: ProviderCredentials) async throws -> Bool

    /// Get authentication headers
    /// - Returns: Headers to include in requests
    func getAuthHeaders() async throws -> [String: String]

    /// Refresh authentication if needed
    func refreshAuthenticationIfNeeded() async throws

    /// Check if authentication is expired
    /// - Returns: Whether authentication has expired
    func isAuthenticationExpired() -> Bool
}
