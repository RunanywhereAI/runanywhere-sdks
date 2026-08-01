// SPDX-License-Identifier: Apache-2.0
//
// `RunAnywhere.models` and `RunAnywhere.lora`.

import 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/download_service.pb.dart'
    show DownloadStage, DownloadState;
import 'package:runanywhere/generated/lora_options.pb.dart'
    show
        LoRAAdapterConfig,
        LoRAApplyRequest,
        LoRARemoveRequest,
        LoraAdapterCatalogEntry,
        LoraAdapterCatalogGetRequest,
        LoraAdapterCatalogQuery;
import 'package:runanywhere/generated/model_types.pb.dart'
    show ModelFileDescriptor, ModelGetRequest, ModelInfo;
import 'package:runanywhere/generated/model_types.pbenum.dart'
    show ModelFileRole;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/public/api/internal/model_gate.dart';
import 'package:runanywhere/public/api/types/events.dart';
import 'package:runanywhere/public/api/types/model_registration.dart';
import 'package:runanywhere/public/api/types/options.dart';
import 'package:runanywhere/public/api/types/results.dart';
import 'package:runanywhere/public/capabilities/runanywhere_downloads.dart';
import 'package:runanywhere/public/capabilities/runanywhere_lora.dart';
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';
import 'package:runanywhere/public/extensions/runanywhere_storage.dart';

bool _registryDirty = true;

/// The model registry: listing, registration, download, and placement.
class ModelsApi {
  /// Bind the namespace. Reach it through `RunAnywhere.models`.
  const ModelsApi();

  static const List<ModelCategory> _loadableCategories = <ModelCategory>[
    ModelCategory.MODEL_CATEGORY_LANGUAGE,
    ModelCategory.MODEL_CATEGORY_MULTIMODAL,
    ModelCategory.MODEL_CATEGORY_VISION,
    ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
    ModelCategory.MODEL_CATEGORY_EMBEDDING,
    ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION,
    ModelCategory.MODEL_CATEGORY_SPEAKER_DIARIZATION,
    ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION,
  ];

  /// Every registered model, narrowed by [filter].
  ///
  /// ```dart
  /// final llms = await RunAnywhere.models.list(
  ///   const ModelFilter(category: ModelCategory.MODEL_CATEGORY_LANGUAGE));
  /// ```
  ///
  /// Throws [SDKException] when the SDK is not initialized.
  Future<List<ModelInfo>> list([ModelFilter? filter]) async {
    if (_registryDirty) {
      _registryDirty = false;
      await RunAnywhereModels.shared.refreshModelRegistry();
    }
    final result = await RunAnywhereModels.shared.list(
      query: filter?.toProto(),
    );
    return List<ModelInfo>.unmodifiable(result.models.models);
  }

  /// The registry entry for [id], or null when it is unknown.
  Future<ModelInfo?> get(String id) async {
    final result = await RunAnywhereModels.shared.getModel(
      ModelGetRequest(modelId: id),
    );
    return result.found ? result.model : null;
  }

  /// Add [model] to the registry and return its entry.
  ///
  /// Throws [SDKException] when registration fails.
  Future<ModelInfo> register(ModelRegistration model) {
    _registryDirty = true;
    switch (model.kind) {
      case ModelArtifactKind.singleFile:
        return RunAnywhereStorage.registerModel(
          id: model.id,
          name: model.name,
          url: model.url!,
          framework: model.framework,
          modality: model.category,
          artifactType: model.artifactType,
          memoryRequirement: model.memoryRequirementBytes,
          supportsThinking: model.supportsThinking,
          supportsLora: model.supportsLora,
        );
      case ModelArtifactKind.archive:
        return RunAnywhereStorage.registerArchiveModel(
          archiveUrl: model.url!,
          structure: model.archiveStructure!,
          id: model.id,
          name: model.name,
          framework: model.framework,
          modality: model.category,
          archiveType: model.archiveType,
          memoryRequirement: model.memoryRequirementBytes,
          supportsThinking: model.supportsThinking,
          supportsLora: model.supportsLora,
        );
      case ModelArtifactKind.multiFile:
        return RunAnywhereStorage.registerMultiFileModel(
          files: _withInferredRoles(model.files, model.category),
          id: model.id!,
          name: model.name,
          framework: model.framework,
          modality: model.category,
          memoryRequirement: model.memoryRequirementBytes,
          contextLength: model.contextLength,
          supportsThinking: model.supportsThinking,
          source: model.source,
        );
    }
  }

  /// Fetch [id] to disk, reporting progress until it is registered.
  ///
  /// Throws [SDKException] into the consumer when the transfer fails or is
  /// cancelled.
  Stream<DownloadEvent> download(String id) async* {
    var extracting = false;
    await for (final progress in RunAnywhereDownloads.shared.start(id)) {
      switch (progress.state) {
        case DownloadState.DOWNLOAD_STATE_FAILED:
          throw SDKException.downloadFailed(
            id,
            progress.hasError() ? progress.error.message : null,
          );
        case DownloadState.DOWNLOAD_STATE_CANCELLED:
          throw SDKException.cancelled('Download cancelled for $id');
        case DownloadState.DOWNLOAD_STATE_COMPLETED:
          final model = await get(id);
          if (model == null) {
            throw SDKException.modelNotFound(id);
          }
          yield DownloadCompleted(model);
        default:
          if (progress.stage == DownloadStage.DOWNLOAD_STAGE_EXTRACTING) {
            if (!extracting) {
              extracting = true;
              yield const DownloadExtracting();
            }
          } else {
            yield DownloadProgressEvent(
              bytesDone: progress.bytesDownloaded.toInt(),
              bytesTotal: progress.totalBytes.toInt(),
              percent: progress.overallProgress > 0
                  ? progress.overallProgress
                  : progress.stageProgress,
            );
          }
      }
    }
  }

  /// Remove [id]'s files from disk and clear its registry path.
  ///
  /// Throws [SDKException] when deletion fails.
  Future<void> delete(String id) async {
    final result = await RunAnywhereStorage.deleteModel(id);
    if (result.hasError()) {
      throw SDKException.storageError(
        result.error.message.isEmpty
            ? 'Failed to delete model: $id'
            : result.error.message,
      );
    }
  }

  /// Make [id] resident, paying the load cost now rather than on first use.
  ///
  /// Throws [SDKException] when the model is unknown or fails to load.
  Future<void> load(String id, {LoadOptions? options}) async {
    final model = await get(id);
    if (model == null) {
      throw SDKException.modelNotFound(id);
    }
    await ModelGate.ensureLoaded(
      modelId: id,
      category: model.category,
      options: options,
    );
  }

  /// Unload the model resident under [category], or everything when null.
  ///
  /// Throws [SDKException] when an unload fails.
  Future<void> unload([ModelCategory? category]) async {
    if (category != null) {
      await ModelGate.unload(category);
      return;
    }
    for (final each in _loadableCategories) {
      await ModelGate.unload(each);
    }
  }

  /// Fill any descriptor whose role is unset using the commons classifier, so
  /// callers never reimplement the SDK's filename conventions.
  static List<ModelFileDescriptor> _withInferredRoles(
    List<ModelFileDescriptor> files,
    ModelCategory category,
  ) => files
      .map((file) {
        if (file.role != ModelFileRole.MODEL_FILE_ROLE_UNSPECIFIED) {
          return file;
        }
        return file.deepCopy()
          ..role = RunAnywhereModels.shared.inferModelFileRole(
            filename: file.filename.isNotEmpty
                ? file.filename
                : file.relativePath,
            modality: category,
          );
      })
      .toList(growable: false);

  /// What is loaded and how much storage the SDK occupies.
  ///
  /// Throws [SDKException] when the SDK is not initialized.
  Future<ModelsState> state() async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    final loaded = <ModelCategory, ModelInfo>{};
    for (final category in _loadableCategories) {
      final id = await ModelGate.currentId(category);
      if (id == null) continue;
      final model = await get(id);
      if (model != null) loaded[category] = model;
    }
    final storage = await RunAnywhereDownloads.shared.getStorageInfo();
    return ModelsState.fromProto(loaded, storage);
  }
}

/// LoRA adapters applied on top of the loaded model.
class LoraApi {
  /// Bind the namespace. Reach it through `RunAnywhere.lora`.
  const LoraApi();

  /// Apply the registered adapter [adapterId] at [scale].
  ///
  /// ```dart
  /// await RunAnywhere.lora.apply('chat-style', 0.8);
  /// ```
  ///
  /// Throws [SDKException] when the adapter is unknown or incompatible.
  Future<void> apply(String adapterId, {double? scale}) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    final lookup = await RunAnywhereLoRACapability.shared.getCatalogEntry(
      LoraAdapterCatalogGetRequest(adapterId: adapterId),
    );
    if (!lookup.found) {
      throw SDKException.modelNotFound(adapterId);
    }
    final entry = lookup.entry;
    final path = entry.localPath;
    if (path.isEmpty) {
      throw SDKException.modelNotDownloaded(
        'LoRA adapter is not on disk: $adapterId',
      );
    }
    final result = await RunAnywhereLoRACapability.shared.apply(
      LoRAApplyRequest(
        adapters: [
          LoRAAdapterConfig(
            adapterPath: path,
            adapterId: adapterId,
            scale:
                scale ??
                (entry.hasDefaultScale() && entry.defaultScale > 0
                    ? entry.defaultScale
                    : 1.0),
          ),
        ],
      ),
    );
    if (result.hasError()) {
      throw SDKException.invalidState(result.error.message);
    }
  }

  /// Remove [adapterId], or every applied adapter when null.
  ///
  /// Throws [SDKException] when the removal fails.
  Future<void> remove([String? adapterId]) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    final request = adapterId == null
        ? LoRARemoveRequest(clearAll: true)
        : LoRARemoveRequest(adapterIds: [adapterId]);
    final state = await RunAnywhereLoRACapability.shared.remove(request);
    if (state.hasError()) {
      throw SDKException.invalidState(state.error.message);
    }
  }

  /// Adapters currently applied to the loaded model.
  ///
  /// Throws [SDKException] when the SDK is not initialized.
  Future<LoraState> list() async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    return LoraState.fromProto(await RunAnywhereLoRACapability.shared.list());
  }

  // --- Beyond the v3 spec -------------------------------------------------
  //
  // Adapters carry base-model compatibility metadata that `models.register`
  // has no field for, so the catalog verbs stay public until the spec covers
  // them.

  /// Add [adapter] to the LoRA catalog and register its downloadable artifact.
  ///
  /// Throws [SDKException] when registration fails.
  Future<void> register(LoraAdapterCatalogEntry adapter) async {
    await RunAnywhereLoRACapability.shared.registerArtifact(adapter);
  }

  /// Catalogued adapters, optionally narrowed to those compatible with
  /// [modelId].
  ///
  /// Throws [SDKException] when the SDK is not initialized.
  Future<List<LoraAdapterCatalogEntry>> catalog({String? modelId}) async {
    if (modelId == null) {
      final result = await RunAnywhereLoRACapability.shared.listCatalog();
      return List<LoraAdapterCatalogEntry>.unmodifiable(result.entries);
    }
    final result = await RunAnywhereLoRACapability.shared.queryCatalog(
      LoraAdapterCatalogQuery(modelId: modelId),
    );
    return List<LoraAdapterCatalogEntry>.unmodifiable(result.entries);
  }

  /// Fetch [adapter]'s weights and return their local path.
  ///
  /// Throws [SDKException] when the transfer fails.
  Future<String> download(
    LoraAdapterCatalogEntry adapter, {
    void Function(double progress)? onProgress,
  }) => RunAnywhereLoRACapability.shared.download(
    adapter,
    onProgress: onProgress,
  );
}
