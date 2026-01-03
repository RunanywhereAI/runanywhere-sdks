import 'dart:async';
// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../public/configuration/sdk_environment.dart';
import '../foundation/logging/sdk_logger.dart';
import 'ffi_types.dart';
import 'platform_loader.dart';

/// Telemetry bridge for C++ telemetry operations.
/// Matches Swift's `CppBridge+Telemetry.swift`.
class DartBridgeTelemetry {
  DartBridgeTelemetry._();

  static final _logger = SDKLogger('DartBridge.Telemetry');
  static final DartBridgeTelemetry instance = DartBridgeTelemetry._();

  static bool _isInitialized = false;
  // ignore: unused_field
  static SDKEnvironment? _environment;

  /// Initialize telemetry manager
  static void initialize(SDKEnvironment environment) {
    if (_isInitialized) return;

    _environment = environment;

    try {
      final lib = PlatformLoader.load();
      final initTelemetry = lib.lookupFunction<
          Int32 Function(Int32),
          int Function(int)>('rac_telemetry_manager_initialize');

      int envValue;
      switch (environment) {
        case SDKEnvironment.development:
          envValue = 0;
          break;
        case SDKEnvironment.staging:
          envValue = 1;
          break;
        case SDKEnvironment.production:
          envValue = 2;
          break;
      }

      final result = initTelemetry(envValue);
      if (result != RacResultCode.success) {
        _logger.warning('Telemetry init failed', metadata: {'code': result});
      }

      _isInitialized = true;
      _logger.debug('Telemetry manager initialized');
    } catch (e) {
      _logger.debug('rac_telemetry_manager_initialize not available: $e');
      _isInitialized = true;
    }
  }

  /// Shutdown telemetry manager
  static void shutdown() {
    if (!_isInitialized) return;

    try {
      final lib = PlatformLoader.load();
      final shutdownFn = lib.lookupFunction<
          Void Function(),
          void Function()>('rac_telemetry_manager_shutdown');

      shutdownFn();
      _isInitialized = false;
      _logger.debug('Telemetry manager shutdown');
    } catch (e) {
      _logger.debug('rac_telemetry_manager_shutdown not available: $e');
    }
  }

  /// Track an event
  Future<void> trackEvent({
    required String eventType,
    Map<String, dynamic>? properties,
    Map<String, dynamic>? metrics,
  }) async {
    try {
      final lib = PlatformLoader.load();
      final trackFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)>('rac_telemetry_track_event');

      final eventJson = jsonEncode({
        'type': eventType,
        'properties': properties,
        'metrics': metrics,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      final jsonPtr = eventJson.toNativeUtf8();
      try {
        trackFn(jsonPtr);
      } finally {
        calloc.free(jsonPtr);
      }
    } catch (e) {
      _logger.debug('rac_telemetry_track_event not available: $e');
    }
  }

  /// Flush pending telemetry
  Future<void> flush() async {
    try {
      final lib = PlatformLoader.load();
      final flushFn = lib.lookupFunction<
          Int32 Function(),
          int Function()>('rac_telemetry_flush');

      flushFn();
    } catch (e) {
      _logger.debug('rac_telemetry_flush not available: $e');
    }
  }

  /// Set user ID for telemetry
  void setUserId(String userId) {
    try {
      final lib = PlatformLoader.load();
      final setUserFn = lib.lookupFunction<
          Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)>('rac_telemetry_set_user_id');

      final idPtr = userId.toNativeUtf8();
      try {
        setUserFn(idPtr);
      } finally {
        calloc.free(idPtr);
      }
    } catch (e) {
      _logger.debug('rac_telemetry_set_user_id not available: $e');
    }
  }

  /// Enable/disable telemetry
  void setEnabled(bool enabled) {
    try {
      final lib = PlatformLoader.load();
      final setEnabledFn = lib.lookupFunction<
          Void Function(Int32),
          void Function(int)>('rac_telemetry_set_enabled');

      setEnabledFn(enabled ? 1 : 0);
    } catch (e) {
      _logger.debug('rac_telemetry_set_enabled not available: $e');
    }
  }

  /// Check if telemetry is enabled
  bool isEnabled() {
    try {
      final lib = PlatformLoader.load();
      final isEnabledFn = lib.lookupFunction<
          Int32 Function(),
          int Function()>('rac_telemetry_is_enabled');

      return isEnabledFn() != 0;
    } catch (e) {
      return true; // Default to enabled
    }
  }
}
