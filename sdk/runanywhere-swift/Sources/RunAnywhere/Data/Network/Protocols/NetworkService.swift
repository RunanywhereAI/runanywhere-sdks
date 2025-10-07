import Foundation

/// Protocol defining the network service interface
/// This allows for environment-based implementations (real vs mock)
public protocol NetworkService: Sendable {
    /// Perform a POST request
    func post<T: Encodable, R: Decodable>(
        _ endpoint: APIEndpoint,
        _ payload: T,
        requiresAuth: Bool
    ) async throws -> R

    /// Perform a GET request
    func get<R: Decodable>(
        _ endpoint: APIEndpoint,
        requiresAuth: Bool
    ) async throws -> R

    /// Perform a raw POST request (returns Data)
    func postRaw(
        _ endpoint: APIEndpoint,
        _ payload: Data,
        requiresAuth: Bool
    ) async throws -> Data

    /// Perform a raw GET request (returns Data)
    func getRaw(
        _ endpoint: APIEndpoint,
        requiresAuth: Bool
    ) async throws -> Data
}

/// Extension to provide default implementations
public extension NetworkService {
    func post<T: Encodable, R: Decodable>(
        _ endpoint: APIEndpoint,
        _ payload: T,
        requiresAuth: Bool = true
    ) async throws -> R {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        let responseData = try await postRaw(endpoint, data, requiresAuth: requiresAuth)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(R.self, from: responseData)
    }

    func get<R: Decodable>(
        _ endpoint: APIEndpoint,
        requiresAuth: Bool = true
    ) async throws -> R {
        let responseData = try await getRaw(endpoint, requiresAuth: requiresAuth)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(R.self, from: responseData)
    }
}
