import Foundation

/// API endpoints
public enum APIEndpoint: Equatable {
    // Authentication & Health
    case authenticate
    case refreshToken
    case healthCheck

    // Device Management - Production/Staging
    case deviceRegistration
    case telemetry

    // Device Management - Development
    case devDeviceRegistration
    case devTelemetry

    // Model Management
    case modelAssignments(deviceType: String, platform: String)
    case modelsAvailable
    case modelDownload(modelId: String)
    // Note: compatibleModels endpoint exists in backend but not used in SDK yet
    // Backend: /api/v1/devices/{device_id}/compatible-models

    var path: String {
        switch self {
        // Authentication & Health
        case .authenticate:
            return "/api/v1/auth/sdk/authenticate"
        case .refreshToken:
            return "/api/v1/auth/sdk/refresh"
        case .healthCheck:
            return "/v1/health"

        // Device Management - Production/Staging
        case .deviceRegistration:
            return "/api/v1/devices/register"
        case .telemetry:
            return "/api/v1/sdk/telemetry"

        // Device Management - Development (Supabase REST API format)
        case .devDeviceRegistration:
            return "/rest/v1/device_registrations"
        case .devTelemetry:
            return "/rest/v1/telemetry_events"  // V2 normalized base table (matches production)

        // Model Management
        case .modelAssignments(let deviceType, let platform):
            return "/api/v1/model-assignments/for-sdk?device_type=\(deviceType)&platform=\(platform)"
        case .modelsAvailable:
            return "/api/v1/models/available"
        case .modelDownload(let modelId):
            return "/api/v1/models/\(modelId)/download"
        }
    }
}

// MARK: - Environment-Based Endpoint Selection

extension APIEndpoint {
    /// Get the device registration endpoint for the given environment
    /// - Parameter environment: The SDK environment
    /// - Returns: The appropriate endpoint (dev or production)
    public static func deviceRegistrationEndpoint(for environment: SDKEnvironment) -> APIEndpoint {
        switch environment {
        case .development:
            return .devDeviceRegistration
        case .staging, .production:
            return .deviceRegistration
        }
    }

    /// Get the telemetry endpoint for the given environment
    /// - Parameter environment: The SDK environment
    /// - Returns: The appropriate endpoint (dev or production)
    public static func telemetryEndpoint(for environment: SDKEnvironment) -> APIEndpoint {
        switch environment {
        case .development:
            return .devTelemetry
        case .staging, .production:
            return .telemetry
        }
    }
}
