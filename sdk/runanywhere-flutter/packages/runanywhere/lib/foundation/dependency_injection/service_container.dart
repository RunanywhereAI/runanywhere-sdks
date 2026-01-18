/// Service Container
///
/// Dependency injection container for SDK services.
/// Matches iOS ServiceContainer from Foundation/DependencyInjection/ServiceContainer.swift
///
/// Note: Most services are now handled via FFI through DartBridge.
/// This container provides minimal DI for platform-specific services.
library service_container;

import 'dart:async';

import 'package:runanywhere/data/network/api_client.dart';
import 'package:runanywhere/data/network/http_service.dart';
import 'package:runanywhere/data/network/network_configuration.dart';
import 'package:runanywhere/data/network/network_service.dart';
import 'package:runanywhere/data/network/telemetry_service.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/dart_bridge_device.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';

/// Service container for dependency injection
/// Matches iOS ServiceContainer from Foundation/DependencyInjection/ServiceContainer.swift
class ServiceContainer {
  /// Shared instance
  static final ServiceContainer shared = ServiceContainer._();

  ServiceContainer._();

  // Network services
  APIClient? _apiClient;
  NetworkService? _networkService;

  // Logger
  SDKLogger? _logger;

  // Internal state - reserved for future use
  // ignore: unused_field
  SDKInitParams? _initParams;

  /// Logger
  SDKLogger get logger {
    return _logger ??= SDKLogger();
  }

  /// API client
  APIClient? get apiClient => _apiClient;

  /// Network service for HTTP operations
  NetworkService? get networkService => _networkService;

  /// HTTP service (new centralized network layer)
  HTTPService get httpService => HTTPService.shared;

  /// Telemetry service
  TelemetryService get telemetryService => TelemetryService.shared;

  /// Set network service (called during initialization)
  void setNetworkService(NetworkService service) {
    _networkService = service;
  }

  /// Create an API client with the given configuration
  APIClient createAPIClient({
    required Uri baseURL,
    required String apiKey,
  }) {
    final client = APIClient(baseURL: baseURL, apiKey: apiKey);
    _apiClient = client;
    _networkService = client;
    return client;
  }

  /// Setup local services (no network calls)
  Future<void> setupLocalServices({
    required String apiKey,
    required Uri baseURL,
    required SDKEnvironment environment,
  }) async {
    // Store init params
    _initParams = SDKInitParams(
      apiKey: apiKey,
      baseURL: baseURL,
      environment: environment,
    );

    // Configure HTTPService (new centralized network layer)
    _configureHTTPService(
      apiKey: apiKey,
      baseURL: baseURL,
      environment: environment,
    );

    // Configure TelemetryService (fetch device ID properly)
    await _configureTelemetryService(
      environment: environment,
    );

    // Create API client for network services (legacy support)
    _apiClient = APIClient(
      baseURL: baseURL,
      apiKey: apiKey,
    );
    _networkService = _apiClient;
  }

  /// Configure the centralized HTTP service
  void _configureHTTPService({
    required String apiKey,
    required Uri baseURL,
    required SDKEnvironment environment,
  }) {
    // Configure main HTTP service
    HTTPService.shared.configure(HTTPServiceConfig(
      baseURL: baseURL.toString(),
      apiKey: apiKey,
      environment: environment,
    ));

    // Configure development mode with Supabase if applicable
    if (environment == SDKEnvironment.development) {
      final supabaseConfig = SupabaseConfig.configuration(environment);
      if (supabaseConfig != null) {
        HTTPService.shared.configureDev(DevModeConfig(
          supabaseURL: supabaseConfig.projectURL.toString(),
          supabaseKey: supabaseConfig.anonKey,
        ));
      }
    }
  }

  /// Configure the telemetry service
  Future<void> _configureTelemetryService({
    required SDKEnvironment environment,
  }) async {
    // Properly fetch device ID - don't use "unknown"
    // This matches Swift/Kotlin which use real device IDs for telemetry
    final deviceId = await DartBridgeDevice.instance.getDeviceId();
    
    TelemetryService.shared.configure(
      deviceId: deviceId,
      environment: environment,
    );

    // Enable telemetry for both development and production
    // - Development: sends to Supabase /rest/v1/telemetry_events
    // - Production: sends to Railway /api/v1/sdk/telemetry
    // Staging is disabled by default (can be overridden by the app)
    final shouldEnable = environment == SDKEnvironment.development ||
        environment == SDKEnvironment.production;
    TelemetryService.shared.setEnabled(shouldEnable);
  }

  /// Reset all services (for testing)
  void reset() {
    _apiClient = null;
    _networkService = null;
    _logger = null;
    _initParams = null;
    HTTPService.resetForTesting();
    TelemetryService.resetForTesting();
  }
}

/// SDK initialization parameters
class SDKInitParams {
  final String apiKey;
  final Uri baseURL;
  final SDKEnvironment environment;

  const SDKInitParams({
    required this.apiKey,
    required this.baseURL,
    required this.environment,
  });
}
