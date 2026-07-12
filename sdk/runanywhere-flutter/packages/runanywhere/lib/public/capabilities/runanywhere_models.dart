// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_models.dart — v4 Models capability. Owns the model
// registry surface: listing available models, refreshing from
// filesystem, and registering new models (single-file + multi-file).

import 'dart:async';

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
import 'package:runanywhere/public/extensions/runanywhere_storage.dart';

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

    // Wait for Phase-2 downloaded-model discovery (best-effort; offline
    // listing of already-registered models must keep working).
    try {
      await DartBridge.ensureServicesReady();
    } catch (_) {
      // Non-fatal: registry contents remain listable.
    }

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

  /// Refresh the model registry. Routes through the commons C ABI
  /// `rac_model_registry_refresh_proto`.
  ///
  /// Matches Swift `RunAnywhere.refreshModelRegistry(rescanLocal:includeRemoteCatalog:pruneOrphans:)`
  /// (RunAnywhere+ModelRegistry.swift:46) — each flag is caller-controlled
  /// with Swift's defaults.
  Future<void> refreshModelRegistry({
    bool rescanLocal = true,
    bool includeRemoteCatalog = false,
    bool pruneOrphans = false,
  }) async {
    if (!DartBridge.isInitialized) return;

    final logger = SDKLogger('RunAnywhere.Discovery');

    if (rescanLocal) {
      final result = await DartBridgeModelRegistry.instance
          .discoverDownloadedModels();
      if (result.discoveredModels.isNotEmpty) {
        logger.info(
          'Discovery found ${result.discoveredModels.length} downloaded models',
        );
      }
    }

    final ok = await DartBridgeModelRegistry.instance.refresh(
      rescanLocal: rescanLocal,
      includeRemoteCatalog: includeRemoteCatalog,
      pruneOrphans: pruneOrphans,
    );
    if (!ok) {
      logger.warning('rac_model_registry_refresh_proto reported failure');
    }
  }

  /// Register a single-file remote model with the SDK.
  ///
  /// Delegates to `rac_register_model_from_url_proto` via
  /// [RunAnywhereStorage.registerModel] and returns the fully-populated
  /// [ModelInfo] proto. Mirrors Swift `RunAnywhere.registerModel(id:name:url:
  /// framework:modality:artifactType:memoryRequirement:supportsThinking:
  /// supportsLora:)` in both signature shape and return type.
  Future<ModelInfo> register({
    String? id,
    required String name,
    required String url,
    required InferenceFramework framework,
    ModelCategory modality = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    ModelArtifactType? artifactType,
    int? memoryRequirement,
    bool supportsThinking = false,
    bool supportsLora = false,
  }) => RunAnywhereStorage.registerModel(
    id: id,
    name: name,
    url: url,
    framework: framework,
    modality: modality,
    artifactType: artifactType,
    memoryRequirement: memoryRequirement,
    supportsThinking: supportsThinking,
    supportsLora: supportsLora,
  );

  /// Register an archive-packaged model (tar.gz / tar.bz2 / tar.xz / zip)
  /// where the caller needs to specify the on-disk layout.
  ///
  /// Delegates to [RunAnywhereStorage.registerArchiveModel]. Mirrors Swift
  /// `RunAnywhere.registerModel(archive:structure:...)`.
  Future<ModelInfo> registerArchiveModel({
    required String archiveUrl,
    required ArchiveStructure structure,
    String? id,
    required String name,
    required InferenceFramework framework,
    ModelCategory modality = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    ArchiveType? archiveType,
    int? memoryRequirement,
    bool supportsThinking = false,
    bool supportsLora = false,
  }) => RunAnywhereStorage.registerArchiveModel(
    archiveUrl: archiveUrl,
    structure: structure,
    id: id,
    name: name,
    framework: framework,
    modality: modality,
    archiveType: archiveType,
    memoryRequirement: memoryRequirement,
    supportsThinking: supportsThinking,
    supportsLora: supportsLora,
  );

  /// Register a multi-file model (e.g. embedding model.onnx + vocab.txt).
  ///
  /// Delegates to [RunAnywhereStorage.registerMultiFileModel]. Mirrors Swift
  /// `RunAnywhere.registerModel(multiFile:id:name:framework:...)`.
  Future<ModelInfo> registerMultiFile({
    required String id,
    required String name,
    required List<ModelFileDescriptor> files,
    required InferenceFramework framework,
    // Mirrors Swift RunAnywhere+Storage.swift:135 (`modality: ModelCategory = .language`).
    ModelCategory modality = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    int? memoryRequirement,
    int? contextLength,
    bool supportsThinking = false,
    ModelSource source = ModelSource.MODEL_SOURCE_REMOTE,
  }) => RunAnywhereStorage.registerMultiFileModel(
    files: files,
    id: id,
    name: name,
    framework: framework,
    modality: modality,
    memoryRequirement: memoryRequirement,
    contextLength: contextLength,
    supportsThinking: supportsThinking,
    source: source,
  );

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
    final roleValue = DartBridge.modelPaths.inferFileRole(
      filename,
      modality.value,
    );
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
    await DartBridge.ensureServicesReady();
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
}
