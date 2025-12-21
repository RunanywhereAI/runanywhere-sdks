import Foundation

/// API endpoints
public enum APIEndpoint: Equatable {
    // Authentication & Health
    case authenticate
    case refreshToken
    case healthCheck

    // Device Management - Production/Staging
    case deviceRegistration
    case analytics

    // Device Management - Development
    case devDeviceRegistration
    case devAnalytics

    // Model Management
    case modelAssignments(deviceType: String, platform: String)

    // Core endpoints
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

        // Device Management - Production/Staging
        case .deviceRegistration:
            return "/api/v1/devices/register"
        case .analytics:
            return "/api/v1/sdk/telemetry"  // Backend uses sdk/telemetry for production

        // Device Management - Development (Supabase REST API format)
        case .devDeviceRegistration:
            return "/rest/v1/device_registrations"
        case .devAnalytics:
            return "/rest/v1/analytics_events"

        // Model Management
        case .modelAssignments(let deviceType, let platform):
            return "/api/v1/model-assignments/for-sdk?device_type=\(deviceType)&platform=\(platform)"

        // Core endpoints
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

    /// Get the analytics endpoint for the given environment
    /// - Parameter environment: The SDK environment
    /// - Returns: The appropriate endpoint (dev or production)
    public static func analyticsEndpoint(for environment: SDKEnvironment) -> APIEndpoint {
        switch environment {
        case .development:
            return .devAnalytics
        case .staging, .production:
            return .analytics
        }
    }
}
