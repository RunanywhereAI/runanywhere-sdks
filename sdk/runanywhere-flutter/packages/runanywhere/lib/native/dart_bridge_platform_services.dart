import 'dart:async';
// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:ffi';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

typedef _PlatformServiceAvailabilityCallbackNative = Int32 Function(
  Int32 service,
  Pointer<Void> userData,
);

/// Platform services bridge for Foundation Models and System TTS.
/// Matches Swift's `CppBridge+Platform.swift`.
class DartBridgePlatformServices {
  DartBridgePlatformServices._();

  static final _logger = SDKLogger('DartBridge.PlatformServices');
  static final DartBridgePlatformServices instance =
      DartBridgePlatformServices._();

  static bool _isRegistered = false;
  static Pointer<NativeFunction<_PlatformServiceAvailabilityCallbackNative>>?
      _availabilityCallback;

  static const int _serviceFoundationModels = 1;
  static const int _serviceSystemTts = 2;
  static const int _serviceSystemStt = 3;
  static const int _exceptionalReturnFalse = 0;

  /// Register platform services with C++
  static Future<void> register() async {
    if (_isRegistered) return;

    try {
      final lib = PlatformLoader.load();

      final registerCallback = lib.lookupFunction<
          Int32 Function(
              Pointer<NativeFunction<Int32 Function(Int32, Pointer<Void>)>>),
          int Function(
              Pointer<NativeFunction<Int32 Function(Int32, Pointer<Void>)>>)>(
        'rac_platform_services_register_availability_callback',
      );

      _availabilityCallback ??=
          Pointer.fromFunction<_PlatformServiceAvailabilityCallbackNative>(
        _availabilityCallbackNative,
        _exceptionalReturnFalse,
      );

      final result = registerCallback(_availabilityCallback!);
      if (result != RacResultCode.success) {
        _logger.warning(
          'Failed to register platform services availability callback',
          metadata: {'error_code': result},
        );
        return;
      }

      _isRegistered = true;
      _logger.debug('Platform services registered');
    } catch (e) {
      // librac_commons.so may not export
      // rac_platform_services_register_availability_callback in some
      // configurations (B-FL-1-002). Log at warning so it's visible in
      // non-debug builds, then mark as registered to avoid retry.
      _logger.warning('Platform services registration not available: $e');
      _isRegistered = true;
    }
  }

  static int _availabilityCallbackNative(
    int service,
    Pointer<Void> userData,
  ) {
    switch (service) {
      case _serviceFoundationModels:
        return 0;
      case _serviceSystemTts:
      case _serviceSystemStt:
        return 1;
      default:
        return 0;
    }
  }

  /// Check if Foundation Models are available (iOS 18+)
  bool isFoundationModelsAvailable() {
    // Foundation Models require iOS 18+
    // This would check platform version in a full implementation
    return false; // Not available on Android or older iOS
  }

  /// Check if System TTS is available
  bool isSystemTTSAvailable() {
    // System TTS is available on all iOS/Android versions
    return true;
  }

  /// Check if System STT is available
  bool isSystemSTTAvailable() {
    // System STT is available on iOS/Android
    return true;
  }

  /// Get available platform services
  List<String> getAvailableServices() {
    final services = <String>[];

    if (isFoundationModelsAvailable()) {
      services.add('foundation_models');
    }
    if (isSystemTTSAvailable()) {
      services.add('system_tts');
    }
    if (isSystemSTTAvailable()) {
      services.add('system_stt');
    }

    return services;
  }
}
