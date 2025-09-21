import Foundation

/// API endpoints
public enum APIEndpoint: Equatable {
    // Authentication & Health
    case authenticate
    case refreshToken
    case healthCheck

    // Device Management
    case registerDevice

    // Model Management
    case modelAssignments(deviceType: String, platform: String)
    case fetchModels
    case fetchModel(id: String)
    case downloadModel(id: String)

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

        // Model Management
        case .modelAssignments:
            return "/api/v1/model-assignments/for-sdk"
        case .fetchModels:
            return "/api/v1/models/available"
        case .fetchModel(let id):
            return "/api/v1/models/\(id)"
        case .downloadModel(let id):
            return "/api/v1/models/\(id)/download"

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

    var queryParameters: [String: String]? {
        switch self {
        case .modelAssignments(let deviceType, let platform):
            return ["device_type": deviceType, "platform": platform]
        default:
            return nil
        }
    }
}
