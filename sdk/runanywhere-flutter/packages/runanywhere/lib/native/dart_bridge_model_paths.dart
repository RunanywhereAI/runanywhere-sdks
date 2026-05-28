import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/model_types.pb.dart';
import 'package:runanywhere/generated/model_types.pbenum.dart' as model_enum;
import 'package:runanywhere/native/dart_bridge_model_registry.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/native/type_conversions/model_types_cpp_bridge.dart';
import 'package:runanywhere/native/types/basic_types.dart';

base class RacResolvedModelFileStruct extends Struct {
  external Pointer<Utf8> relativePath;
  external Pointer<Utf8> path;

  @Int32()
  external int role;

  @Int32()
  external int isRequired;

  @Int32()
  external int exists;
}

base class RacModelPathResolutionStruct extends Struct {
  external Pointer<Utf8> rootPath;
  external Pointer<Utf8> primaryModelPath;
  external Pointer<Utf8> mmprojPath;
  external Pointer<Utf8> tokenizerPath;
  external Pointer<Utf8> configPath;

  external Pointer<RacResolvedModelFileStruct> files;
  @Size()
  external int fileCount;

  external Pointer<Pointer<Utf8>> missingRequiredFiles;
  @Size()
  external int missingRequiredFileCount;

  @Int32()
  external int isDirectoryBased;

  @Int32()
  external int isComplete;

  @Int32()
  external int checksumValidated;

  @Int32()
  external int checksumMatched;
}

class ModelPathResolution {
  final String? rootPath;
  final String? primaryModelPath;
  final String? mmprojPath;
  final String? tokenizerPath;
  final String? configPath;
  final bool isDirectoryBased;
  final bool isComplete;

  const ModelPathResolution({
    required this.rootPath,
    required this.primaryModelPath,
    required this.mmprojPath,
    required this.tokenizerPath,
    required this.configPath,
    required this.isDirectoryBased,
    required this.isComplete,
  });
}

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
  ///
  /// On iOS, `getApplicationDocumentsDirectory()` resolves to
  /// `NSDocumentDirectory` (e.g. `Application/<UUID>/Documents`). This
  /// persists across normal app relaunches on both simulator and physical
  /// device. On a physical device it also persists across App Store /
  /// TestFlight reinstalls (bundle ID is the container key).
  ///
  /// Simulator caveat (expected, not a bug): `xcrun simctl install` will
  /// reuse the existing data container UUID when the app is already
  /// installed, but `simctl uninstall` (or a corrupted container that
  /// forces Xcode to re-provision one) allocates a fresh UUID with an
  /// empty `Documents/`. Previously-downloaded models are then not
  /// discoverable because the SDK correctly scans the NEW container, not
  /// the old one. This mirrors Swift, React Native, and Kotlin behavior.
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
        final result = getDir(framework.toC(), buffer, _pathBufferSize);
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
        final result =
            getFolder(modelIdPtr, framework.toC(), buffer, _pathBufferSize);
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
  /// Delegates to C++ rac_model_paths_resolve_artifact() which handles model
  /// artifact roots, primary model selection, and companion file discovery.
  Future<String?> resolveModelFilePath(ModelInfo model) async {
    return resolveArtifact(model)?.primaryModelPath;
  }

  /// Resolve primary and companion paths for a downloaded model artifact.
  ModelPathResolution? resolveArtifact(ModelInfo model) {
    final artifactRoot = model.localPath.isNotEmpty
        ? model.localPath
        : getModelFolder(model.id, model.framework);
    if (artifactRoot == null || artifactRoot.isEmpty) return null;

    try {
      final lib = PlatformLoader.loadCommons();
      final resolveFn = lib.lookupFunction<
          Int32 Function(
            Pointer<RacModelInfoCStruct>,
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<RacModelPathResolutionStruct>,
          ),
          int Function(
            Pointer<RacModelInfoCStruct>,
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<RacModelPathResolutionStruct>,
          )>('rac_model_paths_resolve_artifact');
      final freeResolutionFn = lib.lookupFunction<
          Void Function(Pointer<RacModelPathResolutionStruct>),
          void Function(Pointer<RacModelPathResolutionStruct>)>(
        'rac_model_path_resolution_free',
      );

      return _withCModelInfo(model, (modelPtr) {
        final rootPtr = artifactRoot.toNativeUtf8();
        final checksumPtr = model.checksumSha256.isEmpty
            ? nullptr
            : model.checksumSha256.toNativeUtf8();
        final resolutionPtr = calloc<RacModelPathResolutionStruct>();
        try {
          final result =
              resolveFn(modelPtr, rootPtr, checksumPtr, resolutionPtr);
          if (result != RacResultCode.success) {
            _logger.debug(
              'rac_model_paths_resolve_artifact failed: '
              'code=$result model=${model.id}',
            );
            return null;
          }
          return _copyResolution(resolutionPtr.ref);
        } finally {
          freeResolutionFn(resolutionPtr);
          calloc.free(rootPtr);
          if (checksumPtr != nullptr) {
            calloc.free(checksumPtr);
          }
          calloc.free(resolutionPtr);
        }
      });
    } catch (e) {
      _logger.debug('rac_model_paths_resolve_artifact error: $e');
      return null;
    }
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

  // MARK: - File Role Inference

  /// Infer the descriptor role for a sidecar filename. Delegates to the shared
  /// commons classifier `rac_infer_model_file_role` so the heuristic stays
  /// byte-identical with the C++ resolver and every other SDK.
  /// [modalityProto] / the return value are proto `ModelCategory` /
  /// `ModelFileRole` int values. Returns the primary-model role (1) on any
  /// FFI failure.
  int inferFileRole(String filename, int modalityProto) {
    try {
      final lib = PlatformLoader.loadCommons();
      final inferFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Int32, Pointer<Int32>),
          int Function(Pointer<Utf8>, int,
              Pointer<Int32>)>('rac_infer_model_file_role');

      final filenamePtr = filename.toNativeUtf8();
      final rolePtr = calloc<Int32>()..value = 1; // MODEL_FILE_ROLE_PRIMARY_MODEL
      try {
        inferFn(filenamePtr, modalityProto, rolePtr);
        return rolePtr.value;
      } finally {
        calloc.free(filenamePtr);
        calloc.free(rolePtr);
      }
    } catch (e) {
      _logger.debug('rac_infer_model_file_role error: $e');
      return 1; // MODEL_FILE_ROLE_PRIMARY_MODEL
    }
  }

  T? _withCModelInfo<T>(
    ModelInfo model,
    T? Function(Pointer<RacModelInfoCStruct>) body,
  ) {
    final lib = PlatformLoader.loadCommons();
    final allocFn = lib.lookupFunction<Pointer<RacModelInfoCStruct> Function(),
        Pointer<RacModelInfoCStruct> Function()>('rac_model_info_alloc');
    final freeFn = lib.lookupFunction<
        Void Function(Pointer<RacModelInfoCStruct>),
        void Function(Pointer<RacModelInfoCStruct>)>('rac_model_info_free');
    final strdupFn = lib.lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>),
        Pointer<Utf8> Function(Pointer<Utf8>)>('rac_strdup');

    final modelPtr = allocFn();
    if (modelPtr == nullptr) return null;

    final idPtr = model.id.toNativeUtf8();
    final namePtr = model.name.toNativeUtf8();
    final downloadUrlPtr =
        model.downloadUrl.isEmpty ? null : model.downloadUrl.toNativeUtf8();
    final localPathPtr =
        model.localPath.isEmpty ? null : model.localPath.toNativeUtf8();
    final descriptionPtr =
        model.description.isEmpty ? null : model.description.toNativeUtf8();

    try {
      modelPtr.ref
        ..id = strdupFn(idPtr)
        ..name = strdupFn(namePtr)
        ..category = model.category.toC()
        ..format = model.format.toC()
        ..framework = model.framework.toC()
        ..downloadUrl =
            downloadUrlPtr == null ? nullptr : strdupFn(downloadUrlPtr)
        ..localPath = localPathPtr == null ? nullptr : strdupFn(localPathPtr)
        ..downloadSize = model.downloadSizeBytes.toInt()
        ..memoryRequired = model.memoryRequiredBytes.toInt()
        ..contextLength = model.contextLength
        ..supportsThinking = model.supportsThinking ? RAC_TRUE : RAC_FALSE
        ..supportsLora = model.supportsLora ? RAC_TRUE : RAC_FALSE
        ..description =
            descriptionPtr == null ? nullptr : strdupFn(descriptionPtr)
        ..source = model.source.toC();

      _fillArtifactInfo(modelPtr.ref.artifactInfo, model);
      return body(modelPtr);
    } finally {
      calloc.free(idPtr);
      calloc.free(namePtr);
      if (downloadUrlPtr != null) calloc.free(downloadUrlPtr);
      if (localPathPtr != null) calloc.free(localPathPtr);
      if (descriptionPtr != null) calloc.free(descriptionPtr);
      freeFn(modelPtr);
    }
  }

  void _fillArtifactInfo(
    RacArtifactInfoStruct artifact,
    ModelInfo model,
  ) {
    artifact
      ..kind = _artifactKind(model)
      ..archiveType = _archiveType(model)
      ..archiveStructure = _archiveStructure(model)
      ..expectedFiles = nullptr
      ..fileDescriptors = nullptr
      ..fileDescriptorCount = 0
      ..strategyId = nullptr;
  }

  int _artifactKind(ModelInfo model) {
    if (model.hasBuiltIn() && model.builtIn) return RacArtifactKind.builtIn;
    if (model.hasCustomStrategyId() && model.customStrategyId.isNotEmpty) {
      return RacArtifactKind.custom;
    }
    if (model.hasMultiFile()) return RacArtifactKind.multiFile;
    if (model.hasArchive()) return RacArtifactKind.archive;

    switch (model.artifactType) {
      case model_enum.ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE:
      case model_enum.ModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE:
        return RacArtifactKind.archive;
      case model_enum.ModelArtifactType.MODEL_ARTIFACT_TYPE_DIRECTORY:
        return RacArtifactKind.multiFile;
      case model_enum.ModelArtifactType.MODEL_ARTIFACT_TYPE_CUSTOM:
        return RacArtifactKind.custom;
      case model_enum.ModelArtifactType.MODEL_ARTIFACT_TYPE_SINGLE_FILE:
      case model_enum.ModelArtifactType.MODEL_ARTIFACT_TYPE_UNSPECIFIED:
      default:
        return RacArtifactKind.singleFile;
    }
  }

  int _archiveType(ModelInfo model) {
    final archiveType = model.hasArchive()
        ? model.archive.type
        : _archiveTypeFromArtifactType(model.artifactType);
    // Delegates to commons' `rac_archive_type_from_proto` via the
    // `ProtoArchiveTypeCppBridge.toC()` extension. Returns
    // `RAC_ARCHIVE_TYPE_NONE` (-1) on UNSPECIFIED / unrecognized inputs,
    // matching the prior hand-written switch.
    return archiveType.toC();
  }

  model_enum.ArchiveType _archiveTypeFromArtifactType(
    model_enum.ModelArtifactType artifactType,
  ) {
    switch (artifactType) {
      case model_enum.ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE:
        return model_enum.ArchiveType.ARCHIVE_TYPE_TAR_GZ;
      case model_enum.ModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE:
        return model_enum.ArchiveType.ARCHIVE_TYPE_ZIP;
      default:
        return model_enum.ArchiveType.ARCHIVE_TYPE_UNSPECIFIED;
    }
  }

  int _archiveStructure(ModelInfo model) {
    final structure = model.hasArchive()
        ? model.archive.structure
        : model_enum.ArchiveStructure.ARCHIVE_STRUCTURE_UNKNOWN;
    // Delegates to commons' `rac_archive_structure_from_proto` via the
    // `ProtoArchiveStructureCppBridge.toC()` extension. Falls back to
    // `RAC_ARCHIVE_STRUCTURE_UNKNOWN` (99) for UNSPECIFIED / unrecognized,
    // matching the prior hand-written switch.
    return structure.toC();
  }

  ModelPathResolution _copyResolution(RacModelPathResolutionStruct resolution) {
    return ModelPathResolution(
      rootPath: _stringOrNull(resolution.rootPath),
      primaryModelPath: _stringOrNull(resolution.primaryModelPath),
      mmprojPath: _stringOrNull(resolution.mmprojPath),
      tokenizerPath: _stringOrNull(resolution.tokenizerPath),
      configPath: _stringOrNull(resolution.configPath),
      isDirectoryBased: resolution.isDirectoryBased == RAC_TRUE,
      isComplete: resolution.isComplete == RAC_TRUE,
    );
  }

  String? _stringOrNull(Pointer<Utf8> value) =>
      value == nullptr ? null : value.toDartString();
}
