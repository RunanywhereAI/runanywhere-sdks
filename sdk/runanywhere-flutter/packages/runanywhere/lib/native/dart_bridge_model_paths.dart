import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/dart_bridge_download.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/native/type_conversions/model_types_cpp_bridge.dart';

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

  /// Resolve the actual model file path for loading.
  /// Delegates to C++ rac_find_model_path_after_extraction() which handles
  /// all model types: ONNX directories, LlamaCpp .gguf files, nested structures.
  Future<String?> resolveModelFilePath(ModelInfo model) async {
    final modelFolder = getModelFolder(model.id, model.framework);
    if (modelFolder == null) return null;

    // Use C++ to find the actual model path (handles all frameworks/formats)
    final resolved = DartBridgeDownload.findModelPathAfterExtraction(
      extractedDir: modelFolder,
      structure: 99, // RAC_ARCHIVE_STRUCTURE_UNKNOWN - auto-detect
      framework: _frameworkToCValue(model.framework),
      format: model.format.toC(),
    );

    return resolved ?? modelFolder;
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
    case InferenceFramework.genie:
      return 11; // RAC_FRAMEWORK_GENIE
    case InferenceFramework.unknown:
      return 99;
  }
}
