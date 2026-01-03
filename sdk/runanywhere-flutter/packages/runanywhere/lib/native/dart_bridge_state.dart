// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../public/configuration/sdk_environment.dart';
import '../foundation/logging/sdk_logger.dart';
import 'ffi_types.dart';
import 'platform_loader.dart';

/// State bridge for C++ SDK state operations.
/// Matches Swift's `CppBridge+State.swift`.
class DartBridgeState {
  DartBridgeState._();

  static final _logger = SDKLogger('DartBridge.State');
  static final DartBridgeState instance = DartBridgeState._();

  /// Initialize C++ state
  void initialize({
    required SDKEnvironment environment,
    String? apiKey,
    String? baseURL,
    String? deviceId,
  }) {
    try {
      final lib = PlatformLoader.load();
      final initState = lib.lookupFunction<
          Int32 Function(Int32, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
          int Function(int, Pointer<Utf8>, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_state_initialize');

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

      final apiKeyPtr = (apiKey ?? '').toNativeUtf8();
      final baseURLPtr = (baseURL ?? '').toNativeUtf8();
      final deviceIdPtr = (deviceId ?? '').toNativeUtf8();

      try {
        final result = initState(envValue, apiKeyPtr, baseURLPtr, deviceIdPtr);
        if (result != RacResultCode.success) {
          _logger.warning('State init failed', metadata: {'code': result});
        }
      } finally {
        calloc.free(apiKeyPtr);
        calloc.free(baseURLPtr);
        calloc.free(deviceIdPtr);
      }
    } catch (e) {
      _logger.debug('rac_state_initialize not available: $e');
    }
  }

  /// Get current environment
  SDKEnvironment? getEnvironment() {
    try {
      final lib = PlatformLoader.load();
      final getEnv = lib.lookupFunction<Int32 Function(), int Function()>(
          'rac_state_get_environment');

      final envValue = getEnv();
      switch (envValue) {
        case 0:
          return SDKEnvironment.development;
        case 1:
          return SDKEnvironment.staging;
        case 2:
          return SDKEnvironment.production;
        default:
          return null;
      }
    } catch (e) {
      _logger.debug('rac_state_get_environment not available: $e');
      return null;
    }
  }

  /// Check if SDK is initialized
  bool isInitialized() {
    try {
      final lib = PlatformLoader.load();
      final isInit = lib.lookupFunction<Int32 Function(), int Function()>(
          'rac_state_is_initialized');

      return isInit() != 0;
    } catch (e) {
      return false;
    }
  }

  /// Get SDK version
  String? getVersion() {
    try {
      final lib = PlatformLoader.load();
      final getVersion = lib.lookupFunction<Pointer<Utf8> Function(),
          Pointer<Utf8> Function()>('rac_get_version');

      final result = getVersion();
      if (result == nullptr) return null;
      return result.toDartString();
    } catch (e) {
      return null;
    }
  }

  /// Get last error message
  String? getLastError() {
    try {
      final lib = PlatformLoader.load();
      final getError = lib.lookupFunction<Pointer<Utf8> Function(),
          Pointer<Utf8> Function()>('rac_get_last_error');

      final result = getError();
      if (result == nullptr) return null;
      return result.toDartString();
    } catch (e) {
      return null;
    }
  }

  /// Reset SDK state
  void reset() {
    try {
      final lib = PlatformLoader.load();
      final resetState = lib
          .lookupFunction<Void Function(), void Function()>('rac_state_reset');

      resetState();
    } catch (e) {
      _logger.debug('rac_state_reset not available: $e');
    }
  }
}
