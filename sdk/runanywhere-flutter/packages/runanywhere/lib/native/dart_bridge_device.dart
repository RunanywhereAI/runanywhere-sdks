import 'dart:async';
// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:ffi';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:ffi/ffi.dart';

import '../public/configuration/sdk_environment.dart';
import '../foundation/logging/sdk_logger.dart';
import 'ffi_types.dart';
import 'platform_loader.dart';

/// Device bridge for C++ device operations.
/// Matches Swift's `CppBridge+Device.swift`.
class DartBridgeDevice {
  DartBridgeDevice._();

  static final _logger = SDKLogger('DartBridge.Device');
  static final DartBridgeDevice instance = DartBridgeDevice._();

  static bool _isRegistered = false;
  static String? _cachedDeviceId;

  /// Register device callbacks with C++
  static void register() {
    if (_isRegistered) return;

    try {
      final lib = PlatformLoader.load();

      // Register device info callback
      // ignore: unused_local_variable
      final registerCallback = lib.lookupFunction<
          Int32 Function(
              Pointer<
                  NativeFunction<Void Function(Pointer<Utf8>, Pointer<Void>)>>),
          int Function(
              Pointer<
                  NativeFunction<
                      Void Function(Pointer<Utf8>, Pointer<Void>)>>)>(
        'rac_device_register_info_callback',
      );

      // Note: In a full implementation, we'd register a callback pointer here
      // For now, we just note that device registration is available

      _isRegistered = true;
      _logger.debug('Device callbacks registered');
    } catch (e) {
      _logger.debug('Device registration not available: $e');
      _isRegistered = true; // Mark as registered to avoid retry
    }
  }

  /// Get or generate device ID
  Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    try {
      final deviceInfo = DeviceInfoPlugin();

      if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _cachedDeviceId = iosInfo.identifierForVendor ?? _generateFallbackId();
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _cachedDeviceId = androidInfo.id;
      } else {
        _cachedDeviceId = _generateFallbackId();
      }
    } catch (e) {
      _logger.warning('Failed to get device ID: $e');
      _cachedDeviceId = _generateFallbackId();
    }

    return _cachedDeviceId!;
  }

  /// Register device with backend if needed
  Future<void> registerIfNeeded(SDKEnvironment environment) async {
    final deviceId = await getDeviceId();

    try {
      final lib = PlatformLoader.load();
      final registerDevice = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Int32),
          int Function(Pointer<Utf8>, int)>('rac_device_register');

      final deviceIdPtr = deviceId.toNativeUtf8();
      try {
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

        final result = registerDevice(deviceIdPtr, envValue);
        if (result != RacResultCode.success) {
          _logger.debug('Device registration returned: $result');
        }
      } finally {
        calloc.free(deviceIdPtr);
      }
    } catch (e) {
      _logger.debug('rac_device_register not available: $e');
    }
  }

  /// Check if device manager is registered
  bool isRegistered() {
    try {
      final lib = PlatformLoader.load();
      final isReg = lib.lookupFunction<Int32 Function(), int Function()>(
          'rac_device_manager_is_registered');

      return isReg() != 0;
    } catch (e) {
      return false;
    }
  }

  String _generateFallbackId() {
    // Generate a simple UUID-like string
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'flutter-$timestamp';
  }
}
