// SPDX-License-Identifier: Apache-2.0
//
// `RunAnywhere.models` and `RunAnywhere.lora`.

import 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/download_service.pb.dart'
    show DownloadState;
import 'package:runanywhere/generated/lora_options.pb.dart'
    show
        LoraAdapterConfig,
        LoraApplyRequest,
        LoraRemoveRequest,
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

  /// Re-read the registry: rescan local storage, optionally pull the remote
  /// catalog, optionally drop entries whose files are gone.
  ///
  /// Matches `models.refresh` on the Swift and Kotlin namespaces, including
  /// its defaults. [list] does a lazy rescan of its own when the registry is
  /// dirty; this is the explicit verb for the other two.
  ///
  /// Deliberately leaves `_registryDirty` alone. `refreshModelRegistry` is a
  /// no-op before the SDK is initialized and logs a native failure rather than
  /// raising, so this method cannot tell a completed refresh from a skipped
  /// one. Clearing the flag here would let a failed refresh cancel [list]'s
  /// pending rescan and serve stale entries; leaving it costs at most one
  /// redundant rescan.
  Future<void> refresh({
    bool rescanLocal = true,
    bool includeRemoteCatalog = false,
    bool pruneOrphans = false,
  }) async {
    await RunAnywhereModels.shared.refreshModelRegistry(
      rescanLocal: rescanLocal,
      includeRemoteCatalog: includeRemoteCatalog,
      pruneOrphans: pruneOrphans,
    );
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
          cuaProfile: model.cuaProfile,
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
          downloadSize: model.downloadSizeBytes,
          contextLength: model.contextLength,
          source: model.source,
          description: model.description,
          supportsThinking: model.supportsThinking,
          supportsLora: model.supportsLora,
          cuaProfile: model.cuaProfile,
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
          description: model.description,
          cuaProfile: model.cuaProfile,
        );
    }
  }

  /// Fetch [id] to disk, reporting progress until it is registered.
  ///
  /// Emits a terminal [DownloadFailed]/[DownloadCancelled] event when the
  /// transfer fails or is cancelled; never fabricates a [DownloadCompleted]
  /// afterward.
  Stream<DownloadEvent> download(String id) async* {
    final operationId = id;
    var sequence = 0;
    yield DownloadStarted(operationId, sequence: sequence++);

    var extracting = false;
    var verifying = false;
    await for (final progress in RunAnywhereDownloads.shared.start(id)) {
      switch (progress.state) {
        case DownloadState.DOWNLOAD_STATE_FAILED:
          yield DownloadFailed(
            operationId,
            progress.hasError()
                ? SDKException.downloadFailed(id, progress.error.message)
                : SDKException.downloadFailed(id),
            sequence: sequence++,
          );
          return;
        case DownloadState.DOWNLOAD_STATE_CANCELLED:
          yield DownloadCancelled(operationId, sequence: sequence++);
          return;
        case DownloadState.DOWNLOAD_STATE_COMPLETED:
          final model = await get(id);
          if (model == null) {
            yield DownloadFailed(
              operationId,
              SDKException.modelNotFound(id),
              sequence: sequence++,
            );
            return;
          }
          yield DownloadCompleted(operationId, model, sequence: sequence++);
          return;
        default:
          // `DownloadStage` was deleted outright (idl/download_service.proto)
          // — it duplicated `DownloadState`; `state` is the single phase
          // field now.
          if (progress.state == DownloadState.DOWNLOAD_STATE_VALIDATING) {
            if (!verifying) {
              verifying = true;
              yield DownloadVerifying(operationId, sequence: sequence++);
            }
          } else if (progress.state == DownloadState.DOWNLOAD_STATE_EXTRACTING) {
            if (!extracting) {
              extracting = true;
              yield DownloadExtracting(
                operationId,
                sequence: sequence++,
                percent: progress.stageProgress > 0
                    ? progress.stageProgress
                    : null,
              );
            }
          } else {
            yield DownloadProgressEvent(
              operationId: operationId,
              bytesDone: progress.bytesDownloaded.toInt(),
              bytesTotal: progress.totalBytes.toInt(),
              sequence: sequence++,
              file: progress.hasCurrentFileName() &&
                      progress.currentFileName.isNotEmpty
                  ? progress.currentFileName
                  : null,
              overallProgress: progress.overallProgress > 0
                  ? progress.overallProgress
                  : null,
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
  /// Only [LoadOptions.backendPreferences]'s first entry (equivalently the
  /// deprecated `framework`) reaches commons today; other placement knobs
  /// are not yet carried by the native load ABI.
  ///
  /// Throws [SDKException] when the model is unknown or fails to load.
  Future<LoadedModel> load(String id, {LoadOptions? options}) async {
    final model = await get(id);
    if (model == null) {
      throw SDKException.modelNotFound(id);
    }
    await ModelGate.ensureLoaded(
      modelId: id,
      category: model.category,
      options: options,
    );
    final preferences = options?.resolvedBackendPreferences ?? const [];
    final requestedBackend = preferences.isEmpty ? null : preferences.first;
    return LoadedModel(
      id: id,
      category: model.category,
      requestedBackend: requestedBackend,
      actualBackend: requestedBackend?.backend ?? model.framework,
      closeHandler: unload,
    );
  }

  /// Release one resident model by [id]. Idempotent — a no-op when [id] is
  /// not loaded.
  ///
  /// Throws [SDKException] when the unload fails.
  Future<void> unload(String id) async {
    final model = await get(id);
    final category = model?.category;
    if (category == null) return;
    final currentId = await ModelGate.currentId(category);
    if (currentId != id) return;
    await ModelGate.unload(category);
  }

  /// Unload the model resident under [category], or every resident model
  /// when null. This is the only category/global unload; [unload] releases
  /// exactly one model by id.
  ///
  /// Throws [SDKException] when an unload fails.
  Future<void> unloadAll([ModelCategory? category]) async {
    if (category != null) {
      await ModelGate.unload(category);
      return;
    }
    for (final each in _loadableCategories) {
      await ModelGate.unload(each);
    }
  }

  /// Remove [id] from the registry. Registration metadata only — [id] must
  /// already be unloaded and have no local artifacts.
  ///
  /// Throws [SDKException] when [id] is unknown, still loaded, or still has
  /// local artifacts; call [unload]/[delete] first.
  Future<void> unregister(String id) async {
    final model = await get(id);
    if (model == null) {
      throw SDKException.modelNotFound(id);
    }
    for (final category in _loadableCategories) {
      final currentId = await ModelGate.currentId(category);
      if (currentId == id) {
        throw SDKException.invalidState(
          "Model '$id' is currently loaded. Call models.unload('$id') before unregister.",
        );
      }
    }
    final hasArtifacts = model.localPath.isNotEmpty;
    if (hasArtifacts) {
      throw SDKException.invalidState(
        "Model '$id' still has local artifacts. Call models.delete('$id') before unregister.",
      );
    }
    _registryDirty = true;
    await RunAnywhereModels.shared.remove(id);
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
      LoraApplyRequest(
        adapters: [
          LoraAdapterConfig(
            adapterPath: path,
            adapterId: adapterId,
            // Leave unset when omitted so commons resolve_effective_lora_scale
            // owns catalog (including 0.0) → 1.0. Proto ctor only sets when non-null.
            scale: scale,
          ),
        ],
        // Stack on top of the currently-applied set (old default behavior,
        // preserved through the replace_existing -> keep_existing polarity
        // inversion: old default `replace_existing=false` meant "stack").
        keepExisting: true,
      ),
    );
    if (result.hasError()) {
      throw SDKException.invalidState(result.error.message);
    }
  }

  /// Remove [adapterId].
  ///
  /// Deprecated v3 adapter: a null (or omitted) [adapterId] forwards to
  /// [removeAll].
  ///
  /// Throws [SDKException] when the removal fails.
  Future<void> remove([String? adapterId]) async {
    if (adapterId == null) {
      return removeAll();
    }
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    final state = await RunAnywhereLoRACapability.shared.remove(
      LoraRemoveRequest(adapterIds: [adapterId]),
    );
    if (state.hasError()) {
      throw SDKException.invalidState(state.error.message);
    }
  }

  /// Remove every applied adapter.
  ///
  /// Throws [SDKException] when the removal fails.
  Future<void> removeAll() async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    final state = await RunAnywhereLoRACapability.shared.remove(
      LoraRemoveRequest(clearAll: true),
    );
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

  /// Add [adapter] to the LoRA catalog and register its downloadable
  /// [artifact].
  ///
  /// `LoraAdapterCatalogEntry` no longer carries url/filename/size/checksum
  /// metadata (idl/lora_options.proto: "everything generic about the
  /// artifact ... lives on the ModelInfo record for this adapter"), so the
  /// caller supplies the [artifact] describing where/how to fetch the
  /// adapter bytes.
  ///
  /// Throws [SDKException] when registration fails.
  Future<void> register(
    LoraAdapterCatalogEntry adapter,
    ModelInfo artifact,
  ) async {
    await RunAnywhereLoRACapability.shared.registerArtifact(adapter, artifact);
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

  /// Fetch [adapter]'s weights (described by [artifact]) and return their
  /// local path.
  ///
  /// Throws [SDKException] when the transfer fails.
  Future<String> download(
    LoraAdapterCatalogEntry adapter,
    ModelInfo artifact, {
    void Function(double progress)? onProgress,
  }) => RunAnywhereLoRACapability.shared.download(
    adapter,
    artifact,
    onProgress: onProgress,
  );
}
