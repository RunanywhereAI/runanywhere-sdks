/// Network Services
///
/// Centralized network layer for RunAnywhere Flutter SDK.
/// HTTP transport is backed by the commons Phase H client
/// (`rac_http_client_*`) via [HTTPClientAdapter].
library network;

// Commons-backed HTTP client (FFI)
export 'package:runanywhere/adapters/http_client_adapter.dart'
    show HTTPClientAdapter, HttpClientResponse, HttpClientException;

// Auth response models
export 'models/auth/authentication_response.dart'
    show AuthenticationResponse, RefreshTokenResponse;

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

// Telemetry
export 'telemetry_service.dart'
    show TelemetryService, TelemetryCategory, TelemetryEvent;
