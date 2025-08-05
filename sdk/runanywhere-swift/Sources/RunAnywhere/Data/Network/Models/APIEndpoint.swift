import Foundation

/// API endpoints for cloud sync
public enum APIEndpoint {
    case syncConfiguration
    case syncTelemetry
    case syncModelMetadata
    case syncGenerationHistory
    case syncUserPreferences

    var path: String {
        switch self {
        case .syncConfiguration:
            return "/v1/sync/configuration"
        case .syncTelemetry:
            return "/v1/sync/telemetry"
        case .syncModelMetadata:
            return "/v1/sync/models"
        case .syncGenerationHistory:
            return "/v1/sync/history"
        case .syncUserPreferences:
            return "/v1/sync/preferences"
        }
    }
}
