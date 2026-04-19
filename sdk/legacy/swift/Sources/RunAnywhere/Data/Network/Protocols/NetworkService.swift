import Foundation

/// Protocol defining the network service interface
/// Takes path strings directly - use C++ RAC_ENDPOINT_* constants
public protocol NetworkService: Sendable {
    /// Perform a POST request
    func post<T: Encodable, R: Decodable>(
        _ path: String,
        _ payload: T,
        requiresAuth: Bool
    ) async throws -> R

    /// Perform a GET request
    func get<R: Decodable>(
        _ path: String,
        requiresAuth: Bool
    ) async throws -> R

    /// Perform a raw POST request (returns Data)
    func postRaw(
        _ path: String,
        _ payload: Data,
        requiresAuth: Bool
    ) async throws -> Data

    /// Perform a raw GET request (returns Data)
    func getRaw(
        _ path: String,
        requiresAuth: Bool
    ) async throws -> Data
}

/// Extension to provide default implementations
public extension NetworkService {
    func post<T: Encodable, R: Decodable>(
        _ path: String,
        _ payload: T,
        requiresAuth: Bool = true
    ) async throws -> R {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        let responseData = try await postRaw(path, data, requiresAuth: requiresAuth)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(R.self, from: responseData)
    }

    func get<R: Decodable>(
        _ path: String,
        requiresAuth: Bool = true
    ) async throws -> R {
        let responseData = try await getRaw(path, requiresAuth: requiresAuth)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(R.self, from: responseData)
    }
}
