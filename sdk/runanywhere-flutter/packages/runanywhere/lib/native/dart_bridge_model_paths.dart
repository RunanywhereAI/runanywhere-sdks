import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

import '../core/types/model_types.dart';
import '../foundation/logging/sdk_logger.dart';
import 'ffi_types.dart';
import 'platform_loader.dart';

/// Model path utilities bridge.
/// Wraps C++ rac_model_paths.h functions.
/// Matches Swift's CppBridge.ModelPaths exactly.
class DartBridgeModelPaths {
  DartBridgeModelPaths._();

  static final _logger = SDKLogger('DartBridge.ModelPaths');
  static final DartBridgeModelPaths instance = DartBridgeModelPaths._();
  static const _pathBufferSize = 1024;

  // MARK: - Configuration

  /// Set the base directory for model storage.
  /// Must be called during SDK initialization.
  /// Matches Swift: CppBridge.ModelPaths.setBaseDirectory()
  Future<void> setBaseDirectory([String? path]) async {
    final dir = path ?? (await getApplicationDocumentsDirectory()).path;

    try {
      final lib = PlatformLoader.loadCommons();
      final setBase = lib.lookupFunction<Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)>('rac_model_paths_set_base_dir');

      final dirPtr = dir.toNativeUtf8();
      try {
        final result = setBase(dirPtr);
        if (result == RacResultCode.success) {
          _logger.debug('C++ base directory set to: $dir');
        } else {
          _logger.warning('Failed to set C++ base directory: $result');
        }
      } finally {
        calloc.free(dirPtr);
      }
    } catch (e) {
      _logger.warning('rac_model_paths_set_base_dir error: $e');
    }
  }

  // MARK: - Directory Paths (C++ wrappers)

  /// Get the models directory from C++.
  /// Returns: `{base_dir}/RunAnywhere/Models/`
  /// Matches Swift: CppBridge.ModelPaths.getModelsDirectory()
  String? getModelsDirectory() {
    try {
      final lib = PlatformLoader.loadCommons();
      final getDir = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, IntPtr),
          int Function(
              Pointer<Utf8>, int)>('rac_model_paths_get_models_directory');

      final buffer = calloc<Uint8>(_pathBufferSize).cast<Utf8>();
      try {
        final result = getDir(buffer, _pathBufferSize);
        if (result == RacResultCode.success) {
          return buffer.toDartString();
        }
      } finally {
        calloc.free(buffer);
      }
    } catch (e) {
      _logger.debug('rac_model_paths_get_models_directory error: $e');
    }
    return null;
  }

  /// Get framework directory from C++.
  /// Returns: `{base_dir}/RunAnywhere/Models/{framework}/`
  /// Matches Swift: CppBridge.ModelPaths.getFrameworkDirectory()
  String? getFrameworkDirectory(InferenceFramework framework) {
    try {
      final lib = PlatformLoader.loadCommons();
      final getDir = lib.lookupFunction<
          Int32 Function(Int32, Pointer<Utf8>, IntPtr),
          int Function(int, Pointer<Utf8>,
              int)>('rac_model_paths_get_framework_directory');

      final buffer = calloc<Uint8>(_pathBufferSize).cast<Utf8>();
      try {
        final result =
            getDir(_frameworkToCValue(framework), buffer, _pathBufferSize);
        if (result == RacResultCode.success) {
          return buffer.toDartString();
        }
      } finally {
        calloc.free(buffer);
      }
    } catch (e) {
      _logger.debug('rac_model_paths_get_framework_directory error: $e');
    }
    return null;
  }

  /// Get model folder from C++.
  /// Returns: `{base_dir}/RunAnywhere/Models/{framework}/{modelId}/`
  /// Matches Swift: CppBridge.ModelPaths.getModelFolder()
  String? getModelFolder(String modelId, InferenceFramework framework) {
    try {
      final lib = PlatformLoader.loadCommons();
      final getFolder = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Int32, Pointer<Utf8>, IntPtr),
          int Function(Pointer<Utf8>, int, Pointer<Utf8>,
              int)>('rac_model_paths_get_model_folder');

      final modelIdPtr = modelId.toNativeUtf8();
      final buffer = calloc<Uint8>(_pathBufferSize).cast<Utf8>();
      try {
        final result = getFolder(
            modelIdPtr, _frameworkToCValue(framework), buffer, _pathBufferSize);
        if (result == RacResultCode.success) {
          return buffer.toDartString();
        }
      } finally {
        calloc.free(modelIdPtr);
        calloc.free(buffer);
      }
    } catch (e) {
      _logger.debug('rac_model_paths_get_model_folder error: $e');
    }
    return null;
  }

  // MARK: - Helper: Get model folder and create if needed
  // Matches Swift: SimplifiedFileManager.getModelFolder()

  /// Get model folder, creating it if it doesn't exist.
  /// This is the main method for download service to use.
  Future<String> getModelFolderAndCreate(
      String modelId, InferenceFramework framework) async {
    // Get path from C++
    final path = getModelFolder(modelId, framework);
    if (path != null) {
      _ensureDirectoryExists(path);
      return path;
    }

    // C++ not configured - throw error (SDK not initialized)
    throw StateError(
        'Model paths not configured. Call RunAnywhere.initialize() first.');
  }

  /// Ensure a directory exists, creating it if needed.
  void _ensureDirectoryExists(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  // MARK: - Model File Resolution
  // Matches Swift: resolveModelFilePath(for:)

  /// Resolve the actual model file path for loading.
  /// For single-file models (LlamaCpp), finds the actual .gguf file.
  /// For directory-based models (ONNX), returns the folder.
  Future<String?> resolveModelFilePath(ModelInfo model) async {
    final modelFolder = getModelFolder(model.id, model.framework);
    if (modelFolder == null) return null;

    // For ONNX models (directory-based), find the model directory
    if (model.framework == InferenceFramework.onnx) {
      return _resolveONNXModelPath(modelFolder, model.id);
    }

    // For single-file models (LlamaCpp), find the actual file
    return _resolveSingleFileModelPath(modelFolder, model);
  }

  /// Resolve ONNX model directory path
  String _resolveONNXModelPath(String modelFolder, String modelId) {
    // Check if there's a nested folder with the model name
    final nestedFolder = '$modelFolder/$modelId';
    if (Directory(nestedFolder).existsSync()) {
      if (_hasONNXModelFiles(nestedFolder)) {
        _logger.info('Found ONNX model at nested path: $nestedFolder');
        return nestedFolder;
      }
    }

    // Check if model files exist directly in the folder
    if (_hasONNXModelFiles(modelFolder)) {
      _logger.info('Found ONNX model at folder: $modelFolder');
      return modelFolder;
    }

    // Scan for any subdirectory with model files
    final dir = Directory(modelFolder);
    if (dir.existsSync()) {
      for (final entity in dir.listSync()) {
        if (entity is Directory && _hasONNXModelFiles(entity.path)) {
          _logger.info('Found ONNX model in subdirectory: ${entity.path}');
          return entity.path;
        }
      }
    }

    // Fallback
    _logger.warning('No ONNX model files found, using: $modelFolder');
    return modelFolder;
  }

  /// Check if directory contains ONNX model files
  bool _hasONNXModelFiles(String directory) {
    final dir = Directory(directory);
    if (!dir.existsSync()) return false;

    try {
      return dir.listSync().any((entity) {
        if (entity is! File) return false;
        final name = entity.path.toLowerCase();
        return name.endsWith('.onnx') ||
            name.endsWith('.ort') ||
            name.contains('encoder') ||
            name.contains('decoder') ||
            name.contains('tokens');
      });
    } catch (e) {
      return false;
    }
  }

  /// Resolve single-file model path (LlamaCpp .gguf files)
  String? _resolveSingleFileModelPath(String modelFolder, ModelInfo model) {
    final dir = Directory(modelFolder);
    if (!dir.existsSync()) {
      _logger.warning('Model folder does not exist: $modelFolder');
      return null;
    }

    // Find the model file
    try {
      for (final entity in dir.listSync()) {
        if (entity is File) {
          final name = entity.path.toLowerCase();
          if (name.endsWith('.gguf') || name.endsWith('.bin')) {
            _logger.info('Found model file: ${entity.path}');
            return entity.path;
          }
        }
      }
    } catch (e) {
      _logger.warning('Error scanning model folder: $e');
    }

    _logger.warning('No model file found in: $modelFolder');
    return null;
  }

  // MARK: - Path Analysis

  /// Extract model ID from a file path
  String? extractModelId(String path) {
    try {
      final lib = PlatformLoader.loadCommons();
      final extractFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Pointer<Utf8>, IntPtr),
          int Function(Pointer<Utf8>, Pointer<Utf8>,
              int)>('rac_model_paths_extract_model_id');

      final pathPtr = path.toNativeUtf8();
      final buffer = calloc<Uint8>(256).cast<Utf8>();
      try {
        final result = extractFn(pathPtr, buffer, 256);
        if (result == RacResultCode.success) {
          return buffer.toDartString();
        }
      } finally {
        calloc.free(pathPtr);
        calloc.free(buffer);
      }
    } catch (e) {
      _logger.debug('rac_model_paths_extract_model_id error: $e');
    }
    return null;
  }

  /// Check if a path is within the models directory
  bool isModelPath(String path) {
    try {
      final lib = PlatformLoader.loadCommons();
      final checkFn = lib.lookupFunction<Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)>('rac_model_paths_is_model_path');

      final pathPtr = path.toNativeUtf8();
      try {
        return checkFn(pathPtr) == 1; // RAC_TRUE
      } finally {
        calloc.free(pathPtr);
      }
    } catch (e) {
      return false;
    }
  }
}

/// Convert InferenceFramework to C++ RAC_FRAMEWORK int
int _frameworkToCValue(InferenceFramework framework) {
  switch (framework) {
    case InferenceFramework.onnx:
      return 0; // RAC_FRAMEWORK_ONNX
    case InferenceFramework.llamaCpp:
      return 1; // RAC_FRAMEWORK_LLAMACPP
    case InferenceFramework.foundationModels:
      return 2; // RAC_FRAMEWORK_FOUNDATION_MODELS
    case InferenceFramework.systemTTS:
      return 3; // RAC_FRAMEWORK_SYSTEM_TTS
    case InferenceFramework.fluidAudio:
      return 4; // RAC_FRAMEWORK_FLUID_AUDIO
    case InferenceFramework.builtIn:
      return 5; // RAC_FRAMEWORK_BUILTIN
    case InferenceFramework.none:
      return 6; // RAC_FRAMEWORK_NONE
    case InferenceFramework.unknown:
      return 99;
  }
}
