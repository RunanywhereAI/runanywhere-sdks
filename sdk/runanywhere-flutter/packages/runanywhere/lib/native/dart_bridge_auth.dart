import 'dart:async';
// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../foundation/logging/sdk_logger.dart';
import 'ffi_types.dart';
import 'platform_loader.dart';

/// Authentication bridge for C++ auth operations.
/// Matches Swift's `CppBridge+Auth.swift`.
class DartBridgeAuth {
  DartBridgeAuth._();

  static final _logger = SDKLogger('DartBridge.Auth');
  static final DartBridgeAuth instance = DartBridgeAuth._();

  /// Set the API key in C++ state
  Future<void> setApiKey(String apiKey) async {
    try {
      final lib = PlatformLoader.load();
      final setKey = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)>('rac_auth_set_api_key');

      final keyPtr = apiKey.toNativeUtf8();
      try {
        final result = setKey(keyPtr);
        if (result != RacResultCode.success) {
          _logger.warning('Failed to set API key', metadata: {'code': result});
        }
      } finally {
        calloc.free(keyPtr);
      }
    } catch (e) {
      _logger.debug('rac_auth_set_api_key not available: $e');
    }
  }

  /// Get the current API key
  String? getApiKey() {
    try {
      final lib = PlatformLoader.load();
      final getKey = lib.lookupFunction<
          Pointer<Utf8> Function(),
          Pointer<Utf8> Function()>('rac_auth_get_api_key');

      final result = getKey();
      if (result == nullptr) return null;

      return result.toDartString();
    } catch (e) {
      _logger.debug('rac_auth_get_api_key not available: $e');
      return null;
    }
  }

  /// Validate API key with backend
  Future<bool> validateApiKey(String apiKey) async {
    // API key validation is typically done server-side
    // This is a placeholder for the C++ bridge call
    return apiKey.isNotEmpty;
  }
}
