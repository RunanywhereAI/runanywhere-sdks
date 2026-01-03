import 'dart:async';
// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../foundation/logging/sdk_logger.dart';
import 'ffi_types.dart';
import 'platform_loader.dart';

/// Storage bridge for C++ storage operations.
/// Matches Swift's `CppBridge+Storage.swift`.
class DartBridgeStorage {
  DartBridgeStorage._();

  static final _logger = SDKLogger('DartBridge.Storage');
  static final DartBridgeStorage instance = DartBridgeStorage._();

  /// Get value from storage
  Future<String?> get(String key) async {
    try {
      final lib = PlatformLoader.load();
      final getFn = lib.lookupFunction<
          Pointer<Utf8> Function(Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>)>('rac_storage_get');

      final keyPtr = key.toNativeUtf8();
      try {
        final result = getFn(keyPtr);
        if (result == nullptr) return null;
        return result.toDartString();
      } finally {
        calloc.free(keyPtr);
      }
    } catch (e) {
      _logger.debug('rac_storage_get not available: $e');
      return null;
    }
  }

  /// Set value in storage
  Future<bool> set(String key, String value) async {
    try {
      final lib = PlatformLoader.load();
      final setFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
          int Function(Pointer<Utf8>, Pointer<Utf8>)>('rac_storage_set');

      final keyPtr = key.toNativeUtf8();
      final valuePtr = value.toNativeUtf8();
      try {
        final result = setFn(keyPtr, valuePtr);
        return result == RacResultCode.success;
      } finally {
        calloc.free(keyPtr);
        calloc.free(valuePtr);
      }
    } catch (e) {
      _logger.debug('rac_storage_set not available: $e');
      return false;
    }
  }

  /// Delete value from storage
  Future<bool> delete(String key) async {
    try {
      final lib = PlatformLoader.load();
      final deleteFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)>('rac_storage_delete');

      final keyPtr = key.toNativeUtf8();
      try {
        final result = deleteFn(keyPtr);
        return result == RacResultCode.success;
      } finally {
        calloc.free(keyPtr);
      }
    } catch (e) {
      _logger.debug('rac_storage_delete not available: $e');
      return false;
    }
  }

  /// Check if key exists in storage
  Future<bool> exists(String key) async {
    try {
      final lib = PlatformLoader.load();
      final existsFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)>('rac_storage_exists');

      final keyPtr = key.toNativeUtf8();
      try {
        return existsFn(keyPtr) != 0;
      } finally {
        calloc.free(keyPtr);
      }
    } catch (e) {
      _logger.debug('rac_storage_exists not available: $e');
      return false;
    }
  }

  /// Clear all storage
  Future<bool> clear() async {
    try {
      final lib = PlatformLoader.load();
      final clearFn = lib.lookupFunction<
          Int32 Function(),
          int Function()>('rac_storage_clear');

      final result = clearFn();
      return result == RacResultCode.success;
    } catch (e) {
      _logger.debug('rac_storage_clear not available: $e');
      return false;
    }
  }
}
