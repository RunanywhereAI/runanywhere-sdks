import 'package:runanywhere/public/configuration/sdk_environment.dart';

/// API endpoints matching iOS APIEndpoint.swift exactly.
///
/// Provides typed endpoint definitions for all backend API routes.
enum APIEndpoint {
  // Authentication & Health
  authenticate,
  refreshToken,
  healthCheck,

  // Device Management - Production/Staging
  deviceRegistration,
  analytics,

  // Device Management - Development
  devDeviceRegistration,
  devAnalytics,

  // Telemetry - Production/Staging
  telemetry,
  // Telemetry - Development
  devTelemetry,

  // Core endpoints
  models,
  deviceInfo,
  generationHistory,
  userPreferences,
  modelAssignments,

  // Development-specific
  devModelAssignments,
}

extension APIEndpointPath on APIEndpoint {
  /// Get the URL path for this endpoint.
  String get path {
    switch (this) {
      // Authentication & Health
      case APIEndpoint.authenticate:
        return '/api/v1/auth/sdk/authenticate';
      case APIEndpoint.refreshToken:
        return '/api/v1/auth/sdk/refresh';
      case APIEndpoint.healthCheck:
        return '/v1/health';

      // Device Management - Production/Staging
      case APIEndpoint.deviceRegistration:
        return '/api/v1/devices/register';
      case APIEndpoint.analytics:
        return '/api/v1/analytics';

      // Device Management - Development (Supabase REST API format)
      case APIEndpoint.devDeviceRegistration:
        return '/rest/v1/sdk_devices';
      case APIEndpoint.devAnalytics:
        return '/rest/v1/analytics_events';

      // Telemetry - Production/Staging
      case APIEndpoint.telemetry:
        return '/api/v1/sdk/telemetry';
      // Telemetry - Development (Supabase REST API format)
      case APIEndpoint.devTelemetry:
        return '/rest/v1/telemetry_events';

      // Core endpoints
      case APIEndpoint.models:
        return '/api/v1/models';
      case APIEndpoint.deviceInfo:
        return '/api/v1/device';
      case APIEndpoint.generationHistory:
        return '/api/v1/history';
      case APIEndpoint.userPreferences:
        return '/api/v1/preferences';
      case APIEndpoint.modelAssignments:
        return '/api/v1/model-assignments/for-sdk';

      // Development-specific (Supabase REST API format)
      case APIEndpoint.devModelAssignments:
        return '/rest/v1/sdk_model_assignments';
    }
  }
}

// MARK: - Environment-Based Endpoint Selection

extension APIEndpointEnvironment on APIEndpoint {
  /// Get the device registration endpoint for the given environment.
  static APIEndpoint deviceRegistrationEndpoint(SDKEnvironment environment) {
    switch (environment) {
      case SDKEnvironment.development:
        return APIEndpoint.devDeviceRegistration;
      case SDKEnvironment.staging:
      case SDKEnvironment.production:
        return APIEndpoint.deviceRegistration;
    }
  }

  /// Get the analytics endpoint for the given environment.
  static APIEndpoint analyticsEndpoint(SDKEnvironment environment) {
    switch (environment) {
      case SDKEnvironment.development:
        return APIEndpoint.devAnalytics;
      case SDKEnvironment.staging:
      case SDKEnvironment.production:
        return APIEndpoint.analytics;
    }
  }

  /// Get the telemetry endpoint for the given environment.
  static APIEndpoint telemetryEndpoint(SDKEnvironment environment) {
    switch (environment) {
      case SDKEnvironment.development:
        return APIEndpoint.devTelemetry;
      case SDKEnvironment.staging:
      case SDKEnvironment.production:
        return APIEndpoint.telemetry;
    }
  }

  /// Get the model assignments endpoint for the given environment.
  static APIEndpoint modelAssignmentsEndpoint(SDKEnvironment environment) {
    switch (environment) {
      case SDKEnvironment.development:
        return APIEndpoint.devModelAssignments;
      case SDKEnvironment.staging:
      case SDKEnvironment.production:
        return APIEndpoint.modelAssignments;
    }
  }
}
