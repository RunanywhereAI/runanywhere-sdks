// SPDX-License-Identifier: Apache-2.0
//
// sdk_init.dart — package-internal initialization helpers shared by
// `RunAnywhereSDK.initialize()` and the capability classes.
//
// Moved out of the old static `RunAnywhere` god-class during Phase C
// of the v2 close-out. These helpers are NOT part of the public API.

import 'dart:async';

import 'package:runanywhere/adapters/http_client_adapter.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/dart_bridge_auth.dart';
import 'package:runanywhere/native/dart_bridge_device.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';

/// Register device with backend if not already registered.
/// Mirrors Swift `CppBridge.Device.registerIfNeeded(environment:)` —
/// MUST run before authentication.
Future<void> registerDeviceIfNeeded(
  SDKInitParams params,
  SDKLogger logger,
) async {
  try {
    await DartBridgeDevice.register(
      environment: params.environment,
      baseURL: params.baseURL.toString(),
    );
    await DartBridgeDevice.instance
        .registerIfNeeded()
        .timeout(const Duration(seconds: 10));
    logger.debug('Device registration check completed');
  } on TimeoutException {
    logger.warning('Device registration timed out (non-critical)');
  } catch (e) {
    logger.warning('Device registration failed (non-critical): $e');
  }
}

/// Authenticate with backend for production/staging environments.
/// Mirrors Swift `CppBridge.Auth.authenticate(apiKey:)`. Non-fatal —
/// offline inference still works if auth fails.
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
    logger.debug('Authenticating with device ID: $deviceId');

    final result = await DartBridgeAuth.instance
        .authenticate(
          apiKey: params.apiKey,
          deviceId: deviceId,
        )
        .timeout(const Duration(seconds: 10));

    if (result.isSuccess) {
      logger.info('Authenticated for ${params.environment.description}');
      if (result.data?.accessToken != null) {
        HTTPClientAdapter.shared.setToken(result.data!.accessToken!);
      }
    } else {
      logger.warning(
        'Authentication failed: ${result.error}',
        metadata: {'environment': params.environment.name},
      );
    }
  } on TimeoutException {
    logger.warning(
      'Authentication timed out (non-critical, offline inference still works)',
      metadata: {'environment': params.environment.name},
    );
  } catch (e) {
    logger.warning(
      'Authentication error: $e',
      metadata: {'environment': params.environment.name},
    );
  }
}

/// One-shot filesystem discovery of downloaded models. Called lazily
/// on first `models.available()` call, not during initialize (so that
/// apps have a chance to register their models first).
Future<void> runDiscovery() async {
  final logger = SDKLogger('RunAnywhere.Discovery');
  logger.debug(
      'Running lazy discovery (models should already be registered)...');

  final result =
      await DartBridgeModelRegistry.instance.discoverDownloadedModels();

  if (result.discoveredModels.isNotEmpty) {
    logger.info(
        '📦 Discovered ${result.discoveredModels.length} downloaded models');
    for (final model in result.discoveredModels) {
      logger.debug(
          '  - ${model.modelId} -> ${model.localPath} (framework: ${model.framework})');
    }
  } else {
    logger.debug('No downloaded models discovered');
  }
}
