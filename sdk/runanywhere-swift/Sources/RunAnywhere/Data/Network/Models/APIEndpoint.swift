import Foundation

/// API endpoints
public enum APIEndpoint {
    // Authentication & Health
    case authenticate
    case refreshToken
    case healthCheck

    // Device Management
    case registerDevice

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
            return "/api/v1/auth/sdk/authenticate"
        case .refreshToken:
            return "/api/v1/auth/sdk/refresh"
        case .healthCheck:
            return "/v1/health"

        // Device Management
        case .registerDevice:
            return "/api/v1/devices/register"

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
