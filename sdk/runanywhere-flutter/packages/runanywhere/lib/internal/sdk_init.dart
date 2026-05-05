// SPDX-License-Identifier: Apache-2.0
//
// sdk_init.dart — package-internal initialization helpers shared by
// `RunAnywhereSDK.initialize()` and the capability classes.
//
// FLT-SDK-INIT-MOVE: collapsed to thin delegates over the C++ commons.
// All previous Dart policy (placeholder regex, URL scheme checks,
// 10-second timeouts, environment-required-auth gating) has moved
// into commons (`rac_env_*`, `rac_validate_*`,
// `rac_device_manager_*`, `rac_auth_*`). Dart's only job here is to
// invoke the bridges in the right order and translate results into
// HTTP-token side-effects on the Dart-side `HTTPClientAdapter`.

import 'dart:async';

import 'package:runanywhere/adapters/http_client_adapter.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/dart_bridge_auth.dart';
import 'package:runanywhere/native/dart_bridge_device.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';

/// Register device with backend. Mirrors Swift
/// `CppBridge.Device.registerIfNeeded(environment:)`. The C++
/// device manager owns gating (skip-on-development, already-registered
/// short-circuit). Dart's only job is to install the HTTP/secure
/// callbacks and invoke the C ABI; failures are logged and swallowed
/// so offline inference still works.
Future<void> registerDeviceIfNeeded(
  SDKInitParams params,
  SDKLogger logger,
) async {
  try {
    await DartBridgeDevice.register(
      environment: params.environment,
      baseURL: params.baseURL.toString(),
    );
    await DartBridgeDevice.instance.registerIfNeeded();
    logger.debug('Device registration check completed');
  } catch (e) {
    logger.warning('Device registration failed (non-critical): $e');
  }
}

/// Authenticate with backend. Mirrors Swift
/// `CppBridge.Auth.authenticate(apiKey:)`. The commons auth manager
/// owns environment / placeholder / URL gating; if commons rejects the
/// config it returns a non-success result and we just log it. On
/// success we forward the access token to `HTTPClientAdapter` so
/// subsequent requests carry it.
Future<void> authenticateWithBackend(
  SDKInitParams params,
  SDKLogger logger,
) async {
  try {
    await DartBridgeAuth.initialize(
      environment: params.environment,
      baseURL: params.baseURL.toString(),
    );

    final deviceId = await DartBridgeDevice.instance.getDeviceId();
    final result = await DartBridgeAuth.instance.authenticate(
      apiKey: params.apiKey,
      deviceId: deviceId,
    );

    if (result.isSuccess) {
      logger.info('Authenticated for ${params.environment.description}');
      final token = result.data?.accessToken;
      if (token != null) {
        HTTPClientAdapter.shared.setToken(token);
      }
    } else {
      logger.debug(
        'Authentication skipped or failed: ${result.error}',
        metadata: {'environment': params.environment.name},
      );
    }
  } catch (e) {
    logger.warning(
      'Authentication error (non-critical): $e',
      metadata: {'environment': params.environment.name},
    );
  }
}

/// One-shot filesystem discovery of downloaded models. Called lazily
/// on first `models.available()` so apps can register their catalog
/// first.
Future<void> runDiscovery() async {
  final logger = SDKLogger('RunAnywhere.Discovery');
  final result =
      await DartBridgeModelRegistry.instance.discoverDownloadedModels();

  if (result.discoveredModels.isNotEmpty) {
    logger.info(
      'Discovered ${result.discoveredModels.length} downloaded models',
    );
  }
}
