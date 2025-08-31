import Foundation

/// API endpoints
public enum APIEndpoint {
    // Authentication & Health
    case authenticate
    case healthCheck

    // Core endpoints
    case configuration
    case telemetry
    case models
    case deviceInfo
    case generationHistory
    case userPreferences

    var path: String {
        switch self {
        // Authentication & Health
        case .authenticate:
            return "/v1/auth/token"
        case .healthCheck:
            return "/v1/health"

        // Core endpoints
        case .configuration:
            return "/v1/configuration"
        case .telemetry:
            return "/v1/telemetry"
        case .models:
            return "/v1/models"
        case .deviceInfo:
            return "/v1/device"
        case .generationHistory:
            return "/v1/history"
        case .userPreferences:
            return "/v1/preferences"
        }
    }
}
