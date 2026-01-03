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
import 'package:runanywhere/data/network/network_service.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
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

  // Internal state
  SDKInitParams? _initParams;

  /// Logger
  SDKLogger get logger {
    return _logger ??= SDKLogger();
  }

  /// API client
  APIClient? get apiClient => _apiClient;

  /// Network service for HTTP operations
  NetworkService? get networkService => _networkService;

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

    // Create API client for network services
    _apiClient = APIClient(
      baseURL: baseURL,
      apiKey: apiKey,
    );
    _networkService = _apiClient;
  }

  /// Reset all services (for testing)
  void reset() {
    _apiClient = null;
    _networkService = null;
    _logger = null;
    _initParams = null;
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
