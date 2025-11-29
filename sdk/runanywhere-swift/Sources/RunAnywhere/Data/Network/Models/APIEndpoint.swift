import Foundation

/// API endpoints
public enum APIEndpoint: Equatable {
    // Authentication & Health
    case authenticate
    case refreshToken
    case healthCheck

    // Device Management
    case registerDevice
    case devDeviceRegistration
    case devAnalytics

    // Model Management
    case modelAssignments(deviceType: String, platform: String)

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
        case .devDeviceRegistration:
            return "/api/v1/devices/register/dev"
        case .devAnalytics:
            return "/api/v1/analytics/dev"

        // Model Management
        case .modelAssignments(let deviceType, let platform):
            return "/api/v1/model-assignments/for-sdk?device_type=\(deviceType)&platform=\(platform)"

        // Core endpoints
        case .configuration:
            return "/api/v1/configuration"
        case .telemetry:
            return "/api/v1/sdk/telemetry"
        case .models:
            return "/api/v1/models"
        case .deviceInfo:
            return "/api/v1/device"
        case .generationHistory:
            return "/api/v1/history"
        case .userPreferences:
            return "/api/v1/preferences"
        }
    }
}
