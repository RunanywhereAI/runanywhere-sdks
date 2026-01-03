import 'dart:async';
// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

import '../foundation/logging/sdk_logger.dart';
import 'ffi_types.dart';
import 'platform_loader.dart';

/// Model paths bridge for C++ model path operations.
/// Matches Swift's `CppBridge+ModelPaths.swift`.
class DartBridgeModelPaths {
  DartBridgeModelPaths._();

  static final _logger = SDKLogger('DartBridge.ModelPaths');
  static final DartBridgeModelPaths instance = DartBridgeModelPaths._();

  String? _baseDirectory;

  /// Get the base directory for models
  Future<String> getBaseDirectory() async {
    if (_baseDirectory != null) return _baseDirectory!;

    final appDir = await getApplicationDocumentsDirectory();
    _baseDirectory = '${appDir.path}/runanywhere/models';

    // Ensure directory exists
    final dir = Directory(_baseDirectory!);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    return _baseDirectory!;
  }

  /// Set the base directory for models in C++
  Future<void> setBaseDirectory([String? path]) async {
    final dir = path ?? await getBaseDirectory();
    _baseDirectory = dir;

    try {
      final lib = PlatformLoader.load();
      final setBase = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)>('rac_model_paths_set_base');

      final dirPtr = dir.toNativeUtf8();
      try {
        final result = setBase(dirPtr);
        if (result != RacResultCode.success) {
          _logger.warning('Failed to set model base directory', metadata: {'code': result});
        }
      } finally {
        calloc.free(dirPtr);
      }
    } catch (e) {
      _logger.debug('rac_model_paths_set_base not available: $e');
    }
  }

  /// Get path for a specific model
  Future<String> getModelPath(String modelId) async {
    final base = await getBaseDirectory();
    return '$base/$modelId';
  }

  /// Get path for model metadata
  Future<String> getMetadataPath(String modelId) async {
    final base = await getBaseDirectory();
    return '$base/$modelId/metadata.json';
  }

  /// Check if a model exists locally
  Future<bool> modelExists(String modelId) async {
    final path = await getModelPath(modelId);
    return Directory(path).existsSync();
  }

  /// Get model file path (the actual model file)
  Future<String?> getModelFilePath(String modelId, String filename) async {
    final modelDir = await getModelPath(modelId);
    final filePath = '$modelDir/$filename';

    if (File(filePath).existsSync()) {
      return filePath;
    }
    return null;
  }

  /// List all downloaded models
  Future<List<String>> listDownloadedModels() async {
    final base = await getBaseDirectory();
    final dir = Directory(base);

    if (!dir.existsSync()) return [];

    final models = <String>[];
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final modelId = entity.path.split('/').last;
        models.add(modelId);
      }
    }
    return models;
  }

  /// Delete a model
  Future<bool> deleteModel(String modelId) async {
    try {
      final path = await getModelPath(modelId);
      final dir = Directory(path);

      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
      return true;
    } catch (e) {
      _logger.error('Failed to delete model', metadata: {
        'modelId': modelId,
        'error': e.toString(),
      });
      return false;
    }
  }

  /// Get total storage used by models
  Future<int> getTotalStorageUsed() async {
    final base = await getBaseDirectory();
    final dir = Directory(base);

    if (!dir.existsSync()) return 0;

    var totalSize = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }
    return totalSize;
  }
}
