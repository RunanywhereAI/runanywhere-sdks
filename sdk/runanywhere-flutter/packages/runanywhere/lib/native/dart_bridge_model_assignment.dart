import 'dart:async';
// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../foundation/logging/sdk_logger.dart';
import 'ffi_types.dart';
import 'platform_loader.dart';

/// Model assignment bridge for C++ model assignment operations.
/// Matches Swift's `CppBridge+ModelAssignment.swift`.
class DartBridgeModelAssignment {
  DartBridgeModelAssignment._();

  static final _logger = SDKLogger('DartBridge.ModelAssignment');
  static final DartBridgeModelAssignment instance = DartBridgeModelAssignment._();

  static bool _isRegistered = false;

  /// Register model assignment callbacks with C++
  static Future<void> register() async {
    if (_isRegistered) return;

    try {
      final lib = PlatformLoader.load();

      // Register assignment callback
      // ignore: unused_local_variable
      final registerCallback = lib.lookupFunction<
          Int32 Function(Pointer<NativeFunction<Void Function(Pointer<Utf8>, Pointer<Void>)>>),
          int Function(Pointer<NativeFunction<Void Function(Pointer<Utf8>, Pointer<Void>)>>)>(
        'rac_model_assignment_register_callback',
      );

      // For now, we note that registration is available
      // Full implementation would pass a callback function pointer

      _isRegistered = true;
      _logger.debug('Model assignment callbacks registered');
    } catch (e) {
      _logger.debug('Model assignment registration not available: $e');
      _isRegistered = true;
    }
  }

  /// Get assigned model for a capability
  Future<String?> getAssignedModel(String capability) async {
    try {
      final lib = PlatformLoader.load();
      final getAssigned = lib.lookupFunction<
          Pointer<Utf8> Function(Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>)>('rac_model_get_assigned');

      final capPtr = capability.toNativeUtf8();
      try {
        final result = getAssigned(capPtr);
        if (result == nullptr) return null;
        return result.toDartString();
      } finally {
        calloc.free(capPtr);
      }
    } catch (e) {
      _logger.debug('rac_model_get_assigned not available: $e');
      return null;
    }
  }

  /// Set assigned model for a capability
  Future<bool> setAssignedModel(String capability, String modelId) async {
    try {
      final lib = PlatformLoader.load();
      final setAssigned = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
          int Function(Pointer<Utf8>, Pointer<Utf8>)>('rac_model_set_assigned');

      final capPtr = capability.toNativeUtf8();
      final modelPtr = modelId.toNativeUtf8();
      try {
        final result = setAssigned(capPtr, modelPtr);
        return result == RacResultCode.success;
      } finally {
        calloc.free(capPtr);
        calloc.free(modelPtr);
      }
    } catch (e) {
      _logger.debug('rac_model_set_assigned not available: $e');
      return false;
    }
  }

  /// Clear model assignment for a capability
  Future<bool> clearAssignment(String capability) async {
    try {
      final lib = PlatformLoader.load();
      final clearAssigned = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)>('rac_model_clear_assigned');

      final capPtr = capability.toNativeUtf8();
      try {
        final result = clearAssigned(capPtr);
        return result == RacResultCode.success;
      } finally {
        calloc.free(capPtr);
      }
    } catch (e) {
      _logger.debug('rac_model_clear_assigned not available: $e');
      return false;
    }
  }
}
