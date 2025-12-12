import Foundation

/// Errors that can occur during repository operations
public enum RepositoryError: LocalizedError {
    case saveFailure(String)
    case fetchFailure(String)
    case deleteFailure(String)
    case syncFailure(String)
    case databaseNotInitialized
    case entityNotFound(String)
    case networkUnavailable
    case networkNotAvailable
    case networkError(Error)
    case networkTimeout

    public var errorDescription: String? {
        switch self {
        case .saveFailure(let message):
            return "Failed to save: \(message)"
        case .fetchFailure(let message):
            return "Failed to fetch: \(message)"
        case .deleteFailure(let message):
            return "Failed to delete: \(message)"
        case .syncFailure(let message):
            return "Failed to sync: \(message)"
        case .databaseNotInitialized:
            return "Database not initialized"
        case .entityNotFound(let id):
            return "Entity not found: \(id)"
        case .networkUnavailable, .networkNotAvailable:
            return "Network unavailable for sync"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .networkTimeout:
            return "Network request timed out"
        }
    }
}
