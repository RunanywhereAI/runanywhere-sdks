import 'package:shared_preferences/shared_preferences.dart';

import '../../../foundation/logging/sdk_logger.dart';
import '../../../public/configuration/sdk_environment.dart';
import '../../../public/events/event_bus.dart';
import '../../../public/events/sdk_event.dart';
import '../../../data/network/network_service.dart';
import '../models/device_info.dart';
import '../models/network/device_registration_request.dart';
import '../models/network/device_registration_response.dart';
import 'device_identity.dart';

/// Unified service for device registration with backend.
///
/// Mirrors iOS `DeviceRegistrationService` from RunAnywhere SDK.
/// Handles registration for development, staging, and production environments.
/// Uses NetworkService for network calls.
/// Device UUID is managed by DeviceIdentity (secure storage persisted).
class DeviceRegistrationService {
  static final DeviceRegistrationService shared = DeviceRegistrationService._();

  DeviceRegistrationService._();

  final _logger = SDKLogger(category: 'DeviceRegistration');

  /// Key for tracking registration status
  static const _registeredKey = 'com.runanywhere.sdk.deviceRegistered';

  // MARK: - Device Info API

  /// Get current device information.
  /// Returns fresh data each time.
  Future<DeviceInfo> get currentDeviceInfo async {
    return await DeviceInfo.fetchCurrent();
  }

  /// Get the persistent device ID (secure storage UUID).
  Future<String> get deviceId async {
    return await DeviceIdentity.persistentUUID;
  }

  // MARK: - Registration API

  /// Register device with backend if not already registered.
  /// Uses NetworkService for network calls.
  /// Works for all environments: development, staging, and production.
  Future<void> registerIfNeeded({
    required NetworkService networkService,
    required SDKEnvironment environment,
  }) async {
    // Skip if already registered
    final registered = await isRegistered;
    if (registered) {
      _logger.debug('Device already registered, skipping');
      return;
    }

    final deviceId = await DeviceIdentity.persistentUUID;
    _logger.info(
        'Registering device: ${deviceId.substring(0, 8)}... [${environment.description}]');

    try {
      final request = await DeviceRegistrationRequest.fromCurrentDevice();
      final endpoint = _getEndpointForEnvironment(environment);

      // Use NetworkService for the request
      // Development mode doesn't require auth, staging/production do
      await networkService.postWithPath<DeviceRegistrationResponse>(
        endpoint,
        request.toJson(),
        requiresAuth: environment != SDKEnvironment.development,
        fromJson: DeviceRegistrationResponse.fromJson,
      );

      await _markAsRegistered();
      EventBus.shared.publish(DeviceRegisteredEvent(deviceId: deviceId));
      _logger.info('Device registration successful');
    } catch (e) {
      // Registration failure is non-critical - log and continue
      EventBus.shared
          .publish(DeviceRegistrationFailedEvent(error: e.toString()));
      _logger.warning('Device registration failed (non-critical): $e');
    }
  }

  /// Check if device is registered.
  Future<bool> get isRegistered async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_registeredKey) ?? false;
  }

  /// Clear registration status (for testing/reset).
  Future<void> clearRegistration() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_registeredKey);
  }

  // MARK: - Private Methods

  Future<void> _markAsRegistered() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_registeredKey, true);
  }

  String _getEndpointForEnvironment(SDKEnvironment environment) {
    // Return appropriate endpoint path based on environment
    switch (environment) {
      case SDKEnvironment.development:
        return '/api/devices/register';
      case SDKEnvironment.staging:
        return '/api/v1/devices/register';
      case SDKEnvironment.production:
        return '/api/v1/devices/register';
    }
  }
}

// MARK: - Device Events

/// Event published when device is successfully registered.
class DeviceRegisteredEvent with SDKEventDefaults implements SDKEvent {
  @override
  final DateTime timestamp = DateTime.now();

  @override
  EventCategory get category => EventCategory.device;

  @override
  String get type => 'device.registered';

  final String deviceId;

  DeviceRegisteredEvent({required this.deviceId});

  @override
  Map<String, String> get properties => {
        'device_id': deviceId.substring(0, 8),
      };

  @override
  String toString() =>
      'DeviceRegisteredEvent(deviceId: ${deviceId.substring(0, 8)}...)';
}

/// Event published when device registration fails.
class DeviceRegistrationFailedEvent with SDKEventDefaults implements SDKEvent {
  @override
  final DateTime timestamp = DateTime.now();

  @override
  EventCategory get category => EventCategory.error;

  @override
  String get type => 'device.registration_failed';

  final String error;

  DeviceRegistrationFailedEvent({required this.error});

  @override
  Map<String, String> get properties => {
        'error': error,
      };

  @override
  String toString() => 'DeviceRegistrationFailedEvent(error: $error)';
}
