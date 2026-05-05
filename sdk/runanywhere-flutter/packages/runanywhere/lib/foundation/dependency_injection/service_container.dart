/// Service Container
///
/// Dependency injection container for SDK services. Most services now
/// live behind the commons C ABI via FFI; this container only wires up
/// the shared HTTP client and a few config bookkeeping fields. Telemetry
/// is fully commons-owned — Flutter no longer ships a Dart-side facade.
library service_container;

import 'dart:async';

import 'package:runanywhere/adapters/http_client_adapter.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/dart_bridge_device.dart';
import 'package:runanywhere/native/dart_bridge_telemetry.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';

class ServiceContainer {
  static final ServiceContainer shared = ServiceContainer._();

  ServiceContainer._();

  SDKLogger? _logger;
  SDKInitParams? _initParams;

  SDKLogger get logger => _logger ??= SDKLogger();

  /// Global HTTP client (commons-backed, FFI).
  HTTPClientAdapter get httpClient => HTTPClientAdapter.shared;

  /// Access the stored init params (if any).
  SDKInitParams? get initParams => _initParams;

  Future<void> setupLocalServices({
    required String apiKey,
    required Uri baseURL,
    required SDKEnvironment environment,
  }) async {
    _initParams = SDKInitParams(
      apiKey: apiKey,
      baseURL: baseURL,
      environment: environment,
    );

    _configureHTTPClient(
      apiKey: apiKey,
      baseURL: baseURL,
      environment: environment,
    );

    await _configureTelemetry(environment: environment);
  }

  void _configureHTTPClient({
    required String apiKey,
    required Uri baseURL,
    required SDKEnvironment environment,
  }) {
    HTTPClientAdapter.shared.configure(
      baseURL: baseURL.toString(),
      apiKey: apiKey,
      environment: environment,
    );

    if (environment == SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT) {
      final supabaseConfig = SupabaseConfig.configuration(environment);
      if (supabaseConfig != null) {
        HTTPClientAdapter.shared.configureDev(
          supabaseURL: supabaseConfig.projectURL.toString(),
          supabaseKey: supabaseConfig.anonKey,
        );
      }
    }
  }

  Future<void> _configureTelemetry({
    required SDKEnvironment environment,
  }) async {
    // Commons-owned telemetry manager handles its own init lifecycle. The
    // SDK only needs to ensure the HTTP transport is configured (above) and
    // perform the Phase 2 initialization that wires device info.
    final deviceId = await DartBridgeDevice.instance.getDeviceId();
    DartBridgeTelemetry.initializeSync(environment: environment);
    await DartBridgeTelemetry.initialize(
      environment: environment,
      deviceId: deviceId,
      baseURL: HTTPClientAdapter.shared.isConfigured
          ? _initParams?.baseURL.toString()
          : null,
    );
  }

  void reset() {
    _logger = null;
    _initParams = null;
    HTTPClientAdapter.shared.resetForTesting();
  }
}
