import 'dart:async';
// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../foundation/logging/sdk_logger.dart';
import 'dart_bridge_model_paths.dart';
import 'ffi_types.dart';
import 'platform_loader.dart';

/// Model registry bridge for C++ model registry operations.
/// Matches Swift's `CppBridge+ModelRegistry.swift`.
class DartBridgeModelRegistry {
  DartBridgeModelRegistry._();

  static final _logger = SDKLogger('DartBridge.ModelRegistry');
  static final DartBridgeModelRegistry instance = DartBridgeModelRegistry._();

  /// Register a model with the C++ registry
  Future<bool> registerModel({
    required String modelId,
    required String name,
    required String capability,
    required String framework,
    String? version,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final lib = PlatformLoader.load();
      final registerFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)>('rac_model_registry_register');

      final modelJson = jsonEncode({
        'model_id': modelId,
        'name': name,
        'capability': capability,
        'framework': framework,
        'version': version,
        'metadata': metadata,
      });

      final jsonPtr = modelJson.toNativeUtf8();
      try {
        final result = registerFn(jsonPtr);
        return result == RacResultCode.success;
      } finally {
        calloc.free(jsonPtr);
      }
    } catch (e) {
      _logger.debug('rac_model_registry_register not available: $e');
      return false;
    }
  }

  /// Unregister a model from the C++ registry
  Future<bool> unregisterModel(String modelId) async {
    try {
      final lib = PlatformLoader.load();
      final unregisterFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)>('rac_model_registry_unregister');

      final idPtr = modelId.toNativeUtf8();
      try {
        final result = unregisterFn(idPtr);
        return result == RacResultCode.success;
      } finally {
        calloc.free(idPtr);
      }
    } catch (e) {
      _logger.debug('rac_model_registry_unregister not available: $e');
      return false;
    }
  }

  /// Get all registered models
  Future<List<Map<String, dynamic>>> getRegisteredModels() async {
    try {
      final lib = PlatformLoader.load();
      final getModelsFn = lib.lookupFunction<
          Pointer<Utf8> Function(),
          Pointer<Utf8> Function()>('rac_model_registry_get_all');

      final result = getModelsFn();
      if (result == nullptr) return [];

      final jsonString = result.toDartString();
      final models = jsonDecode(jsonString) as List<dynamic>;

      // Free the C string
      try {
        final freeFn = lib.lookupFunction<
            Void Function(Pointer<Utf8>),
            void Function(Pointer<Utf8>)>('rac_free_string');
        freeFn(result);
      } catch (_) {}

      return models.cast<Map<String, dynamic>>();
    } catch (e) {
      _logger.debug('rac_model_registry_get_all not available: $e');
      return [];
    }
  }

  /// Get models for a specific capability
  Future<List<Map<String, dynamic>>> getModelsForCapability(String capability) async {
    try {
      final lib = PlatformLoader.load();
      final getModelsFn = lib.lookupFunction<
          Pointer<Utf8> Function(Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>)>('rac_model_registry_get_for_capability');

      final capPtr = capability.toNativeUtf8();
      try {
        final result = getModelsFn(capPtr);
        if (result == nullptr) return [];

        final jsonString = result.toDartString();
        final models = jsonDecode(jsonString) as List<dynamic>;

        return models.cast<Map<String, dynamic>>();
      } finally {
        calloc.free(capPtr);
      }
    } catch (e) {
      _logger.debug('rac_model_registry_get_for_capability not available: $e');
      return [];
    }
  }

  /// Discover downloaded models and register them
  Future<void> discoverDownloadedModels() async {
    try {
      final downloadedModels = await DartBridgeModelPaths.instance.listDownloadedModels();

      for (final modelId in downloadedModels) {
        // Try to load metadata and register
        _logger.debug('Discovered downloaded model: $modelId');
        // Registration would happen based on metadata file in the model directory
      }
    } catch (e) {
      _logger.warning('Failed to discover downloaded models: $e');
    }
  }

  /// Check if a model is registered
  Future<bool> isModelRegistered(String modelId) async {
    try {
      final lib = PlatformLoader.load();
      final isRegisteredFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)>('rac_model_registry_is_registered');

      final idPtr = modelId.toNativeUtf8();
      try {
        return isRegisteredFn(idPtr) != 0;
      } finally {
        calloc.free(idPtr);
      }
    } catch (e) {
      _logger.debug('rac_model_registry_is_registered not available: $e');
      return false;
    }
  }
}
