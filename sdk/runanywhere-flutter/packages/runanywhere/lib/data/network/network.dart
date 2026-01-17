/// Network Services
///
/// Centralized network layer for RunAnywhere Flutter SDK.
/// Uses the http package for HTTP requests.
///
/// Matches React Native SDK network layer structure.
library network;

// Core HTTP service
export 'http_service.dart' show HTTPService;

// Configuration utilities
export 'network_configuration.dart'
    show
        HTTPServiceConfig,
        DevModeConfig,
        NetworkConfig,
        SupabaseNetworkConfig,
        createNetworkConfig,
        getEnvironmentName,
        isDevelopment,
        isProduction,
        isStaging;

// API endpoints
export 'api_endpoint.dart'
    show
        APIEndpoint,
        APIEndpointPath,
        APIEndpointEnvironment,
        ModelAssignmentsEndpoint;

// Network service protocol
export 'network_service.dart' show NetworkService;

// API client
export 'api_client.dart' show APIClient, AuthTokenProvider;

// Telemetry
export 'telemetry_service.dart'
    show TelemetryService, TelemetryCategory, TelemetryEvent;

// Models
export 'models/auth/authentication_response.dart'
    show AuthenticationResponse, RefreshTokenResponse;
