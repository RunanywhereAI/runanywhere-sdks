import 'dart:async';
// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:ffi';

import '../foundation/logging/sdk_logger.dart';
import 'platform_loader.dart';

/// Platform services bridge for Foundation Models and System TTS.
/// Matches Swift's `CppBridge+Platform.swift`.
class DartBridgePlatformServices {
  DartBridgePlatformServices._();

  static final _logger = SDKLogger('DartBridge.PlatformServices');
  static final DartBridgePlatformServices instance = DartBridgePlatformServices._();

  static bool _isRegistered = false;

  /// Register platform services with C++
  static Future<void> register() async {
    if (_isRegistered) return;

    try {
      final lib = PlatformLoader.load();

      // Register platform service availability callback
      // ignore: unused_local_variable
      final registerCallback = lib.lookupFunction<
          Int32 Function(Pointer<NativeFunction<Int32 Function(Int32, Pointer<Void>)>>),
          int Function(Pointer<NativeFunction<Int32 Function(Int32, Pointer<Void>)>>)>(
        'rac_platform_services_register_availability_callback',
      );

      // For now, we note that registration is available
      // Full implementation would check iOS/macOS Foundation Models availability

      _isRegistered = true;
      _logger.debug('Platform services registered');
    } catch (e) {
      _logger.debug('Platform services registration not available: $e');
      _isRegistered = true;
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
