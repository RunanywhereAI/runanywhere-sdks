// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_models.dart — v4 Models capability. Owns the model
// registry surface: listing available models, refreshing from
// filesystem, and registering new models (single-file + multi-file).

import 'dart:async';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;
import 'package:runanywhere/core/types/model_types.dart' as legacy;
import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/model_types.pb.dart';
import 'package:runanywhere/internal/sdk_init.dart';
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart'
    hide ModelInfo;
import 'package:runanywhere/native/type_conversions/model_types_cpp_bridge.dart';

/// Model registry capability surface.
///
/// Access via `RunAnywhereSDK.instance.models`.
class RunAnywhereModels {
  RunAnywhereModels._();
  static final RunAnywhereModels _instance = RunAnywhereModels._();
  static RunAnywhereModels get shared => _instance;

  /// All available models from the C++ registry, merged with metadata
  /// from Dart-registered generated ModelInfo entries.
  ///
  /// Runs one-shot filesystem discovery on first call.
  Future<List<ModelInfo>> available() async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }

    if (!SdkState.shared.hasRunDiscovery) {
      await runDiscovery();
      SdkState.shared.hasRunDiscovery = true;
    }

    final cppModels =
        await DartBridgeModelRegistry.instance.getAllProtoModels();

    final uniqueModels = <String, ModelInfo>{};

    for (final model in cppModels) {
      uniqueModels[model.id] = model;
    }

    for (final dartModel in SdkState.shared.registeredModels) {
      final existing = uniqueModels[dartModel.id];
      if (existing != null) {
        uniqueModels[dartModel.id] = _mergeRegistryModel(
          registered: dartModel,
          existing: existing,
        );
      } else {
        uniqueModels[dartModel.id] = dartModel;
      }
    }

    return List.unmodifiable(uniqueModels.values.toList());
  }

  /// Generated-proto registry list surface.
  Future<ModelListResult> list({ModelQuery? query}) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }

    final models = query == null
        ? await available()
        : await DartBridgeModelRegistry.instance.queryProtoModels(query);
    return ModelListResult(
      success: true,
      models: ModelInfoList(models: models),
    );
  }

  /// Generated-proto registry query surface.
  Future<ModelListResult> query(ModelQuery query) => list(query: query);

  /// Generated-proto downloaded-model registry surface.
  Future<ModelListResult> listDownloaded() async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }

    final models =
        await DartBridgeModelRegistry.instance.listDownloadedProtoModels();
    return ModelListResult(
      success: true,
      models: ModelInfoList(models: models),
    );
  }

  /// Refresh the model registry — canonical §13 cross-SDK unified
  /// surface (0-arg). Routes through the commons C ABI
  /// `rac_model_registry_refresh`; rescans local filesystem and
  /// fetches the backend catalog in one shot.
  Future<void> refreshModelRegistry() async {
    if (!SdkState.shared.isInitialized) return;

    final logger = SDKLogger('RunAnywhere.Discovery');

    final result =
        await DartBridgeModelRegistry.instance.discoverDownloadedModels();
    if (result.discoveredModels.isNotEmpty) {
      logger.info(
          'Discovery found ${result.discoveredModels.length} downloaded models');
    }

    final ok = await DartBridgeModelRegistry.instance.refresh(
      includeRemoteCatalog: true,
      pruneOrphans: false,
    );
    if (!ok) {
      logger.warning('rac_model_registry_refresh reported failure');
    }
  }

  /// Register a single-file model with the SDK.
  ///
  /// Mirrors Swift `RunAnywhere.registerModel(...)`. Saves the model
  /// to the C++ registry (fire-and-forget) so the backend can
  /// discover and load it.
  ModelInfo register({
    String? id,
    required String name,
    required Uri url,
    required Object framework,
    Object modality = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    Object? artifactType,
    int? memoryRequirement,
    bool supportsThinking = false,
  }) {
    final modelId =
        id ?? name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-');
    final format = protoModelFormatFromPath(url.path);
    final protoFramework = _frameworkFromAny(framework);
    final protoCategory = _categoryFromAny(modality);

    final baseModel = ModelInfo(
      id: modelId,
      name: name,
      category: protoCategory,
      format: format,
      framework: protoFramework,
      downloadUrl: url.toString(),
      downloadSizeBytes: fixnum.Int64(memoryRequirement ?? 0),
      supportsThinking: supportsThinking,
      source: ModelSource.MODEL_SOURCE_LOCAL,
    );
    final model = _applyArtifact(baseModel, artifactType);

    SdkState.shared.registeredModels.add(model);
    _saveToCppRegistry(model);
    return model;
  }

  /// Register a multi-file model (e.g. embedding model.onnx + vocab.txt).
  ModelInfo registerMultiFile({
    String? id,
    required String name,
    required List<Object> files,
    required Object framework,
    Object modality = ModelCategory.MODEL_CATEGORY_EMBEDDING,
    int? memoryRequirement,
  }) {
    final modelId =
        id ?? name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-');
    final protoFiles = files.map(_fileDescriptorFromAny).toList();
    final primaryUrl = protoFiles.isNotEmpty && protoFiles.first.url.isNotEmpty
        ? protoFiles.first.url
        : null;

    final model = ModelInfo(
      id: modelId,
      name: name,
      category: _categoryFromAny(modality),
      format: ModelFormat.MODEL_FORMAT_ONNX,
      framework: _frameworkFromAny(framework),
      downloadUrl: primaryUrl ?? '',
      multiFile: MultiFileArtifact(files: protoFiles),
      artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_DIRECTORY,
      downloadSizeBytes: fixnum.Int64(memoryRequirement ?? 0),
      source: ModelSource.MODEL_SOURCE_LOCAL,
    );

    SdkState.shared.registeredModels.add(model);
    _saveToCppRegistry(model);
    return model;
  }

  /// Update the download status / local path for a model in the C++
  /// registry. Called by `ModelDownloadService` after a successful
  /// download.
  Future<void> updateDownloadStatus(String modelId, String? localPath) =>
      DartBridgeModelRegistry.instance.updateDownloadStatus(modelId, localPath);

  /// Remove a model from the C++ registry (called on delete).
  Future<void> remove(String modelId) =>
      DartBridgeModelRegistry.instance.removeModel(modelId);

  // -- private helpers ------------------------------------------------------

  static ModelInfo _mergeRegistryModel({
    required ModelInfo registered,
    required ModelInfo existing,
  }) {
    final merged = registered.deepCopy();
    if (existing.localPath.isNotEmpty) merged.localPath = existing.localPath;
    if (existing.downloadSizeBytes > fixnum.Int64.ZERO) {
      merged.downloadSizeBytes = existing.downloadSizeBytes;
    }
    if (existing.createdAtUnixMs > fixnum.Int64.ZERO) {
      merged.createdAtUnixMs = existing.createdAtUnixMs;
    }
    if (existing.updatedAtUnixMs > fixnum.Int64.ZERO) {
      merged.updatedAtUnixMs = existing.updatedAtUnixMs;
    }
    return merged;
  }

  static void _saveToCppRegistry(ModelInfo model) {
    unawaited(
      DartBridgeModelRegistry.instance.saveProtoModel(model).then((success) {
        final logger = SDKLogger('RunAnywhere.Models');
        if (!success) {
          logger.warning('Failed to save model to C++ registry: ${model.id}');
        }
      }).catchError((Object error) {
        SDKLogger('RunAnywhere.Models')
            .error('Error saving model to C++ registry: $error');
      }),
    );
  }

  static ModelCategory _categoryFromAny(Object? value) {
    if (value is ModelCategory) return value;
    if (value is legacy.ModelCategory) return value.toProto();
    return ModelCategory.MODEL_CATEGORY_LANGUAGE;
  }

  static InferenceFramework _frameworkFromAny(Object value) {
    if (value is InferenceFramework) return value;
    if (value is legacy.InferenceFramework) return value.toProto();
    return InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN;
  }

  static ModelFileDescriptor _fileDescriptorFromAny(Object value) {
    if (value is ModelFileDescriptor) return value;
    if (value is legacy.ModelFileDescriptor) {
      return ModelFileDescriptor(
        url: value.url?.toString() ?? '',
        filename: value.destinationPath,
        isRequired: value.isRequired,
        checksum: value.checksumSha256 ?? '',
      );
    }
    throw ArgumentError.value(value, 'files', 'Unsupported model file type');
  }

  static ModelInfo _applyArtifact(ModelInfo model, Object? artifactType) {
    if (artifactType == null) return withInferredArtifact(model);

    if (artifactType is ModelArtifactType) {
      return model.deepCopy()..artifactType = artifactType;
    }
    if (artifactType is ArchiveArtifact) {
      return model.deepCopy()
        ..archive = artifactType
        ..artifactType = _artifactTypeForArchive(artifactType.type);
    }
    if (artifactType is MultiFileArtifact) {
      return model.deepCopy()
        ..multiFile = artifactType
        ..artifactType = ModelArtifactType.MODEL_ARTIFACT_TYPE_DIRECTORY;
    }
    if (artifactType is legacy.BuiltInArtifact) {
      return model.deepCopy()
        ..builtIn = true
        ..artifactType = ModelArtifactType.MODEL_ARTIFACT_TYPE_DIRECTORY;
    }
    if (artifactType is legacy.ArchiveArtifact) {
      final archive = ArchiveArtifact(
        type: _archiveTypeFromLegacy(artifactType.archiveType),
        structure: _archiveStructureFromLegacy(artifactType.structure),
      );
      return model.deepCopy()
        ..archive = archive
        ..artifactType = _artifactTypeForArchive(archive.type);
    }
    if (artifactType is legacy.MultiFileArtifact) {
      final files = artifactType.files.map(_fileDescriptorFromAny).toList();
      return model.deepCopy()
        ..multiFile = MultiFileArtifact(files: files)
        ..artifactType = ModelArtifactType.MODEL_ARTIFACT_TYPE_DIRECTORY;
    }
    if (artifactType is legacy.CustomArtifact) {
      return model.deepCopy()
        ..customStrategyId = artifactType.strategyId
        ..artifactType = ModelArtifactType.MODEL_ARTIFACT_TYPE_CUSTOM;
    }
    return withInferredArtifact(model);
  }

  static ArchiveType _archiveTypeFromLegacy(legacy.ArchiveType type) {
    switch (type) {
      case legacy.ArchiveType.zip:
        return ArchiveType.ARCHIVE_TYPE_ZIP;
      case legacy.ArchiveType.tarBz2:
        return ArchiveType.ARCHIVE_TYPE_TAR_BZ2;
      case legacy.ArchiveType.tarGz:
        return ArchiveType.ARCHIVE_TYPE_TAR_GZ;
      case legacy.ArchiveType.tarXz:
        return ArchiveType.ARCHIVE_TYPE_TAR_XZ;
    }
  }

  static ArchiveStructure _archiveStructureFromLegacy(
    legacy.ArchiveStructure structure,
  ) {
    switch (structure) {
      case legacy.ArchiveStructure.singleFileNested:
        return ArchiveStructure.ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED;
      case legacy.ArchiveStructure.directoryBased:
        return ArchiveStructure.ARCHIVE_STRUCTURE_DIRECTORY_BASED;
      case legacy.ArchiveStructure.nestedDirectory:
        return ArchiveStructure.ARCHIVE_STRUCTURE_NESTED_DIRECTORY;
      case legacy.ArchiveStructure.unknown:
        return ArchiveStructure.ARCHIVE_STRUCTURE_UNKNOWN;
    }
  }

  static ModelArtifactType _artifactTypeForArchive(ArchiveType archiveType) {
    switch (archiveType) {
      case ArchiveType.ARCHIVE_TYPE_TAR_GZ:
        return ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE;
      case ArchiveType.ARCHIVE_TYPE_ZIP:
        return ModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE;
      default:
        return ModelArtifactType.MODEL_ARTIFACT_TYPE_CUSTOM;
    }
  }
}
