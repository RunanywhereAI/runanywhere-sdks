import Foundation
import SQLite3

/// Core database protocol for SQLite operations
public protocol DatabaseCore: Actor {
    /// Execute a SQL statement
    func execute(_ sql: String, parameters: [Any]) async throws

    /// Query data from the database
    func query(_ sql: String, parameters: [Any]) async throws -> [[String: Any]]

    /// Run a transaction
    func transaction<T>(_ block: @escaping (DatabaseCore) async throws -> T) async throws -> T
}
