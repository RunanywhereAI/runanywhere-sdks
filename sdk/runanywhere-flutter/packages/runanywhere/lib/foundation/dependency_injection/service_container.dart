/// Service Container
///
/// Dependency injection container for SDK services. Most services now
/// live behind the commons C ABI via FFI; this container only wires up
/// the shared HTTP client and telemetry service plus a few config
/// bookkeeping fields.
library service_container;

import 'dart:async';

import 'package:runanywhere/adapters/http_client_adapter.dart';
import 'package:runanywhere/data/network/telemetry_service.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/dart_bridge_device.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';

class ServiceContainer {
  static final ServiceContainer shared = ServiceContainer._();

  ServiceContainer._();

  SDKLogger? _logger;
  SDKInitParams? _initParams;

  SDKLogger get logger => _logger ??= SDKLogger();

  /// Global HTTP client (commons-backed, FFI).
  HTTPClientAdapter get httpClient => HTTPClientAdapter.shared;

  /// Telemetry service.
  TelemetryService get telemetryService => TelemetryService.shared;

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

    await _configureTelemetryService(environment: environment);
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

    if (environment == SDKEnvironment.development) {
      final supabaseConfig = SupabaseConfig.configuration(environment);
      if (supabaseConfig != null) {
        HTTPClientAdapter.shared.configureDev(
          supabaseURL: supabaseConfig.projectURL.toString(),
          supabaseKey: supabaseConfig.anonKey,
        );
      }
    }
  }

  Future<void> _configureTelemetryService({
    required SDKEnvironment environment,
  }) async {
    final deviceId = await DartBridgeDevice.instance.getDeviceId();
    TelemetryService.shared.configure(
      deviceId: deviceId,
      environment: environment,
    );

    final shouldEnable = environment == SDKEnvironment.development ||
        environment == SDKEnvironment.production;
    TelemetryService.shared.setEnabled(shouldEnable);
  }

  void reset() {
    _logger = null;
    _initParams = null;
    HTTPClientAdapter.shared.resetForTesting();
    TelemetryService.resetForTesting();
  }
}
