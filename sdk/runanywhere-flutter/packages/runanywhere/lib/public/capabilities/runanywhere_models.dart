// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_models.dart — v4 Models capability. Owns the model
// registry surface: listing available models, refreshing from
// filesystem, and registering new models (single-file + multi-file).

import 'dart:async';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/model_types.pb.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart';
import 'package:runanywhere/public/capabilities/runanywhere_llm.dart';
import 'package:runanywhere/public/capabilities/runanywhere_stt.dart';
import 'package:runanywhere/public/capabilities/runanywhere_tts.dart';
import 'package:runanywhere/public/capabilities/runanywhere_vad.dart';
import 'package:runanywhere/public/capabilities/runanywhere_vlm.dart';
import 'package:runanywhere/public/runanywhere.dart';

/// Model registry capability surface.
///
/// Access via `RunAnywhere.models`.
class RunAnywhereModels {
  RunAnywhereModels._();
  static final RunAnywhereModels _instance = RunAnywhereModels._();
  static RunAnywhereModels get shared => _instance;

  /// All available models from the C++ registry.
  ///
  /// Runs one-shot filesystem discovery on first call. Dart registration writes
  /// generated ModelInfo bytes into commons; this list does not maintain a
  /// parallel Dart registry.
  Future<List<ModelInfo>> available() async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    await RunAnywhere.runDiscoveryIfNeeded();

    final cppModels = await DartBridgeModelRegistry.instance
        .getAllProtoModels();
    return List.unmodifiable(cppModels);
  }

  /// Generated-proto registry list surface.
  Future<ModelListResult> list({ModelQuery? query}) async {
    if (!DartBridge.isInitialized) {
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
  ///
  /// Mirrors Swift `RunAnywhere.queryModels(_:)`.
  Future<ModelListResult> queryModels(ModelQuery query) => list(query: query);

  /// Generated-proto registry query surface. Backwards-compatible shim that
  /// forwards to [queryModels]; prefer [queryModels] for new code.
  Future<ModelListResult> query(ModelQuery query) => queryModels(query);

  /// Generated-proto registry get-by-id surface.
  ///
  /// Mirrors Swift `RunAnywhere.getModel(_:)`.
  Future<ModelGetResult> getModel(ModelGetRequest request) async {
    if (!DartBridge.isInitialized) {
      return ModelGetResult(found: false, errorMessage: 'SDK not initialized');
    }
    final model = await DartBridgeModelRegistry.instance.getProtoModel(
      request.modelId,
    );
    if (model == null) {
      return ModelGetResult(found: false);
    }
    return ModelGetResult(found: true, model: model);
  }

  /// All downloaded models. Mirrors Swift `RunAnywhere.downloadedModels()`.
  Future<ModelListResult> downloadedModels() async {
    return queryModels(ModelQuery(downloadedOnly: true));
  }

  /// Generated-proto downloaded-model registry surface.
  Future<ModelListResult> listDownloaded() async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    final models = await DartBridgeModelRegistry.instance
        .listDownloadedProtoModels();
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
    if (!DartBridge.isInitialized) return;

    final logger = SDKLogger('RunAnywhere.Discovery');

    final result = await DartBridgeModelRegistry.instance
        .discoverDownloadedModels();
    if (result.discoveredModels.isNotEmpty) {
      logger.info(
        'Discovery found ${result.discoveredModels.length} downloaded models',
      );
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
    required InferenceFramework framework,
    ModelCategory modality = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    Object? artifactType,
    int? memoryRequirement,
    bool supportsThinking = false,
  }) {
    final modelId =
        id ?? name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-');
    final format = DartBridgeModelFormat.shared.formatFromUrl(url.path);

    final baseModel = ModelInfo(
      id: modelId,
      name: name,
      category: modality,
      format: format,
      framework: framework,
      downloadUrl: url.toString(),
      downloadSizeBytes: fixnum.Int64(memoryRequirement ?? 0),
      supportsThinking: supportsThinking,
      source: ModelSource.MODEL_SOURCE_LOCAL,
    );
    final model = _applyArtifact(baseModel, artifactType);

    _saveToCppRegistry(model);
    return model;
  }

  /// Register a multi-file model (e.g. embedding model.onnx + vocab.txt).
  ModelInfo registerMultiFile({
    String? id,
    required String name,
    required List<ModelFileDescriptor> files,
    required InferenceFramework framework,
    ModelCategory modality = ModelCategory.MODEL_CATEGORY_EMBEDDING,
    int? memoryRequirement,
  }) {
    final modelId =
        id ?? name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-');
    final protoFiles = files;
    final primaryUrl = protoFiles.isNotEmpty && protoFiles.first.url.isNotEmpty
        ? protoFiles.first.url
        : null;

    final model = ModelInfo(
      id: modelId,
      name: name,
      category: modality,
      format: ModelFormat.MODEL_FORMAT_ONNX,
      framework: framework,
      downloadUrl: primaryUrl ?? '',
      multiFile: MultiFileArtifact(files: protoFiles),
      artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_DIRECTORY,
      downloadSizeBytes: fixnum.Int64(memoryRequirement ?? 0),
      source: ModelSource.MODEL_SOURCE_LOCAL,
    );

    _saveToCppRegistry(model);
    return model;
  }

  /// Infer the canonical [ModelFileRole] for a single sidecar filename in a
  /// multi-file model. Mirrors Swift's
  /// `RunAnywhere.inferModelFileRole(filename:modality:)` and delegates to the
  /// shared commons classifier `rac_infer_model_file_role`, so the SDK and the
  /// C++ model-paths resolver always agree on which file is the primary model,
  /// the vision projector (`mmproj`), tokenizer, vocabulary, etc.
  ///
  /// Only [ModelCategory.MODEL_CATEGORY_MULTIMODAL] enables the `mmproj` match
  /// path. Returns [ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL] when the
  /// filename matches none of the documented sidecar conventions.
  ModelFileRole inferModelFileRole({
    required String filename,
    required ModelCategory modality,
  }) {
    final roleValue =
        DartBridge.modelPaths.inferFileRole(filename, modality.value);
    return ModelFileRole.valueOf(roleValue) ??
        ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL;
  }

  /// Update the download status / local path for a model in the C++
  /// registry. Called after a successful generated-proto download completes.
  /// download.
  Future<void> updateDownloadStatus(String modelId, String? localPath) =>
      DartBridgeModelRegistry.instance.updateDownloadStatus(modelId, localPath);

  /// Remove a model from the C++ registry (called on delete).
  Future<void> remove(String modelId) =>
      DartBridgeModelRegistry.instance.removeModel(modelId);

  /// Polymorphic load entry — dispatches on [ModelInfo.category] so callers
  /// do not hand-roll a per-capability switch.
  ///
  /// Mirrors Swift `RunAnywhere.loadModel(_:)` which routes `RAModelInfo` to
  /// the right component lifecycle. Categories without a dedicated capability
  /// fall through to the LLM lifecycle as the generic default, matching
  /// Swift's behaviour.
  Future<void> loadModel(ModelInfo model) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    switch (model.category) {
      case ModelCategory.MODEL_CATEGORY_LANGUAGE:
        return RunAnywhereLLM.shared.load(model.id);
      case ModelCategory.MODEL_CATEGORY_MULTIMODAL:
      case ModelCategory.MODEL_CATEGORY_VISION:
        return RunAnywhereVLM.shared.load(model.id);
      case ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION:
        return RunAnywhereSTT.shared.load(model.id);
      case ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS:
        return RunAnywhereTTS.shared.loadVoice(model.id);
      case ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION:
        return RunAnywhereVAD.shared.loadModel(model.id);
      default:
        return RunAnywhereLLM.shared.load(model.id);
    }
  }

  /// Polymorphic unload entry — dispatches on [ModelInfo.category]. Mirrors
  /// Swift `RunAnywhere.unloadModel(_:)` with category routing.
  Future<void> unloadModel(ModelInfo model) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    switch (model.category) {
      case ModelCategory.MODEL_CATEGORY_LANGUAGE:
        return RunAnywhereLLM.shared.unload();
      case ModelCategory.MODEL_CATEGORY_MULTIMODAL:
      case ModelCategory.MODEL_CATEGORY_VISION:
        return RunAnywhereVLM.shared.unload();
      case ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION:
        return RunAnywhereSTT.shared.unload();
      case ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS:
        return RunAnywhereTTS.shared.unloadVoice();
      case ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION:
        return RunAnywhereVAD.shared.unloadModel();
      default:
        return RunAnywhereLLM.shared.unload();
    }
  }

  /// Currently-loaded model id for a given [category], or null when nothing
  /// is loaded. Lets callers do the "already-loaded?" check without
  /// hand-rolling a per-capability switch.
  Future<String?> currentLoadedId(ModelCategory category) async {
    switch (category) {
      case ModelCategory.MODEL_CATEGORY_LANGUAGE:
        final m = await RunAnywhereLLM.shared.currentModel();
        return m?.id;
      case ModelCategory.MODEL_CATEGORY_MULTIMODAL:
      case ModelCategory.MODEL_CATEGORY_VISION:
        return RunAnywhereVLM.shared.currentModelId;
      case ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION:
        return RunAnywhereSTT.shared.currentModelId;
      case ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS:
        return RunAnywhereTTS.shared.currentVoiceId;
      case ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION:
        return RunAnywhereVAD.shared.currentModelId;
      default:
        final m = await RunAnywhereLLM.shared.currentModel();
        return m?.id;
    }
  }

  /// Resolve the primary load target for a generated [ModelInfo].
  ///
  /// Delegates artifact layout, archive shape, and companion-file handling to
  /// the commons model-path resolver so callers do not scan model directories
  /// or infer filenames in Dart.
  Future<String> resolveModelFilePath(ModelInfo model) {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    final resolution = DartBridge.modelPaths.resolveArtifact(model);
    final path = resolution?.primaryModelPath;
    if (resolution == null ||
        !resolution.isComplete ||
        path == null ||
        path.isEmpty) {
      throw SDKException.modelNotFound(
        'Could not resolve complete model artifact for: ${model.id}',
      );
    }
    return Future.value(path);
  }

  // -- private helpers ------------------------------------------------------

  static void _saveToCppRegistry(ModelInfo model) {
    unawaited(
      DartBridgeModelRegistry.instance
          .saveProtoModel(model)
          .then((success) {
            final logger = SDKLogger('RunAnywhere.Models');
            if (!success) {
              logger.warning(
                'Failed to save model to C++ registry: ${model.id}',
              );
            }
          })
          .catchError((Object error) {
            SDKLogger(
              'RunAnywhere.Models',
            ).error('Error saving model to C++ registry: $error');
          }),
    );
  }

  static ModelInfo _applyArtifact(ModelInfo model, Object? artifactType) {
    if (artifactType == null) {
      return DartBridgeModelFormat.shared.applyInferredArtifact(model);
    }

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
    return DartBridgeModelFormat.shared.applyInferredArtifact(model);
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
