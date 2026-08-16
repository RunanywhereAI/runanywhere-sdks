/**
 * `RunAnywhere.models` — registry, download, and placement.
 */

import {
  ArchiveStructure,
  ModelArtifactType,
  ModelCategory,
  ModelGetRequest,
  ModelListRequest,
  ModelLoadRequest,
  ModelQuery,
  ModelRegistryStatus,
  ModelUnloadRequest,
  type ModelInfo,
} from '@runanywhere/proto-ts/model_types';
import { DownloadState } from '@runanywhere/proto-ts/download_service';

import { SDKException } from '../../Foundation/Errors/SDKException';
import { ErrorCategory, ErrorCode } from '@runanywhere/proto-ts/errors';
import type { SDKError } from '@runanywhere/proto-ts/errors';
import {
  downloadModelStream,
  getModel as getModelProto,
  listModels,
  queryModels,
  refreshModelRegistry,
  registerArchiveModel,
  registerModel as registerUrlModel,
  registerMultiFileModel,
  removeModel,
} from '../Extensions/Models/RunAnywhere+ModelRegistry';
import {
  loadModel,
  modelInfoForCategory,
  unloadModel,
} from '../Extensions/Models/RunAnywhere+ModelLifecycle';
import { deleteModel } from '../Extensions/Storage/RunAnywhere+Storage';
import { getStorageInfo } from '../Extensions/Storage/RunAnywhere+Storage';
import { mapStream } from './Stream';
import { isNativeModuleAvailable, requireNativeModule } from '../../native';
import type {
  DownloadEvent,
  LoadedModel,
  LoadOptions,
  ModelFilter,
  ModelRegistration,
  ModelsState,
} from './Types';
import { resolvedBackendPreferences, unsupportedLoadOptionKeys } from './LoadOptionsSupport';

const CATEGORIES: ModelCategory[] = [
  ModelCategory.MODEL_CATEGORY_LANGUAGE,
  ModelCategory.MODEL_CATEGORY_VISION,
  ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
  ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
  ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
  ModelCategory.MODEL_CATEGORY_EMBEDDING,
  ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION,
  ModelCategory.MODEL_CATEGORY_SPEAKER_DIARIZATION,
  ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION,
];

const archiveStructureByLayout: Record<
  NonNullable<ModelRegistration['archiveLayout']>,
  ArchiveStructure
> = {
  singleFile: ArchiveStructure.ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED,
  directory: ArchiveStructure.ARCHIVE_STRUCTURE_DIRECTORY_BASED,
  nestedDirectory: ArchiveStructure.ARCHIVE_STRUCTURE_NESTED_DIRECTORY,
};

/** Infer the archive artifact type from a download url extension. */
function inferArtifactType(url: string): ModelArtifactType {
  const lower = url.split('?')[0]?.toLowerCase() ?? '';
  if (lower.endsWith('.zip')) return ModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE;
  if (lower.endsWith('.tar.bz2') || lower.endsWith('.tbz2')) {
    return ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_BZ2_ARCHIVE;
  }
  if (lower.endsWith('.tar.xz') || lower.endsWith('.txz')) {
    return ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_XZ_ARCHIVE;
  }
  return ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE;
}

/**
 * `ModelQuery.availableOnly` is deleted outright — `registryStatus` (set on
 * `ModelInfo`, not `ModelQuery`) is the only downloaded/available-ness axis
 * left on the query message. `ModelFilter.availableOnly` has no wire
 * counterpart to carry it in, so it is dropped here (the caller's request is
 * silently a no-op rather than throwing, matching `downloadedOnly`'s
 * best-effort filter semantics).
 */
function toModelQuery(filter: ModelFilter): ModelQuery {
  return ModelQuery.fromPartial({
    ...(filter.category !== undefined ? { category: filter.category } : {}),
    ...(filter.framework !== undefined ? { framework: filter.framework } : {}),
    ...(filter.downloadedOnly !== undefined
      ? { downloadedOnly: filter.downloadedOnly }
      : {}),
    ...(filter.search ? { searchQuery: filter.search } : {}),
  });
}

function toDownloadEvent(
  progress: Parameters<typeof toDownloadEventInput>[0],
  model: ModelInfo,
  operationId: string,
  sequence: () => number
): DownloadEvent | undefined {
  return toDownloadEventInput(progress, model, operationId, sequence);
}

/**
 * `DownloadStage` is deleted from `download_service.proto` outright —
 * `DownloadProgress.state` (`DownloadState`) is the single phase signal now
 * (matches the same simplification already applied in
 * `RunAnywhere+ModelRegistry.ts`).
 */
function toDownloadEventInput(
  progress: {
    state: DownloadState;
    bytesDownloaded: number;
    totalBytes: number;
    overallProgress: number;
    error?: SDKError | undefined;
  },
  model: ModelInfo,
  operationId: string,
  sequence: () => number
): DownloadEvent | undefined {
  if (progress.state === DownloadState.DOWNLOAD_STATE_FAILED) {
    const error = progress.error
      ? new SDKException(progress.error)
      : SDKException.of(
          ErrorCode.ERROR_CODE_DOWNLOAD_FAILED,
          `download failed for ${model.id}`,
          { category: ErrorCategory.ERROR_CATEGORY_NETWORK }
        );
    return { type: 'failed', operationId, sequence: sequence(), error };
  }
  if (progress.state === DownloadState.DOWNLOAD_STATE_COMPLETED) {
    return { type: 'completed', operationId, sequence: sequence(), model };
  }
  if (progress.state === DownloadState.DOWNLOAD_STATE_EXTRACTING) {
    return { type: 'extracting', operationId, sequence: sequence() };
  }
  const bytesTotal = Number(progress.totalBytes);
  const bytesDone = Number(progress.bytesDownloaded);
  const overall = progress.overallProgress;
  // Commons owns percent policy via rac_download_progress_percent. When the
  // Nitro bind is unavailable, surface indeterminate (omit percent) — never
  // invent overall*100-else-0 that discards a usable bytes ratio.
  let percent: number | undefined;
  if (isNativeModuleAvailable()) {
    percent = requireNativeModule().downloadProgressPercent(
      Number.isFinite(overall) ? overall : -1,
      bytesDone,
      bytesTotal
    );
    // Match Swift: treat ABI 0 as indeterminate when both inputs are unusable.
    if (
      percent === 0 &&
      !(Number.isFinite(overall) && overall >= 0 && overall <= 1) &&
      !(bytesTotal > 0 && bytesDone >= 0)
    ) {
      percent = undefined;
    }
  }
  return {
    type: 'progress',
    operationId,
    sequence: sequence(),
    bytesDone,
    bytesTotal,
    ...(percent !== undefined ? { percent } : {}),
  };
}

/**
 * Fetch one registered model, or `null` when the registry has no such id.
 */
async function get(id: string): Promise<ModelInfo | null> {
  const result = await getModelProto(ModelGetRequest.fromPartial({ modelId: id }));
  return result.found ? (result.model ?? null) : null;
}

async function requireModel(id: string): Promise<ModelInfo> {
  const model = await get(id);
  if (!model) throw SDKException.modelNotFound(id);
  return model;
}

/** Registry, download, and placement control for on-device models. */
export const models = {
  /**
   * List registered models, narrowed by `filter`.
   *
   * @example
   * const chatModels = await RunAnywhere.models.list({ category: ModelCategory.MODEL_CATEGORY_LANGUAGE });
   */
  async list(filter?: ModelFilter): Promise<ModelInfo[]> {
    const result = filter
      ? await queryModels(toModelQuery(filter))
      : await listModels(ModelListRequest.fromPartial({}));
    return result.models?.models ?? [];
  },

  /** Fetch one registered model by id. */
  get,

  /**
   * Add a model to the registry from a url, an archive, or a multi-file set.
   *
   * @throws SDKException when the registration is missing a source or the
   * registry rejects it.
   */
  async register(model: ModelRegistration): Promise<ModelInfo> {
    const shared = {
      name: model.name,
      framework: model.framework ?? 0,
      ...(model.id ? { id: model.id } : {}),
      ...(model.category !== undefined ? { modality: model.category } : {}),
      ...(model.memoryRequirementBytes !== undefined
        ? { memoryRequirement: model.memoryRequirementBytes }
        : {}),
      ...(model.supportsThinking !== undefined
        ? { supportsThinking: model.supportsThinking }
        : {}),
      ...(model.supportsLora !== undefined
        ? { supportsLora: model.supportsLora }
        : {}),
      ...(model.cuaProfile ? { cuaProfile: model.cuaProfile } : {}),
    };

    if (model.files && model.files.length > 0) {
      if (!model.id) {
        throw SDKException.invalidInput(
          'A multi-file ModelRegistration needs an explicit id'
        );
      }
      return registerMultiFileModel({
        ...shared,
        id: model.id,
        files: model.files.map((file) => ({
          url: file.url,
          filename: file.filename,
          isRequired: file.required ?? true,
        })),
      });
    }
    if (model.archiveUrl) {
      // Without an explicit layout, commons' url factory infers the archive
      // structure while extracting; a stated layout needs the explicit
      // archive-artifact path.
      if (!model.archiveLayout) {
        return registerUrlModel({
          ...shared,
          url: model.archiveUrl,
          artifactType: inferArtifactType(model.archiveUrl),
        });
      }
      return registerArchiveModel({
        ...shared,
        url: model.archiveUrl,
        structure: archiveStructureByLayout[model.archiveLayout],
      });
    }
    if (model.url) {
      return registerUrlModel({ ...shared, url: model.url });
    }
    throw SDKException.invalidInput(
      'ModelRegistration needs a url, an archiveUrl, or a files list'
    );
  },

  /**
   * Download a registered model, reporting progress and completion.
   *
   * @throws SDKException when the model is unknown or the transfer fails.
   */
  download(id: string): AsyncIterable<DownloadEvent> {
    return {
      [Symbol.asyncIterator]() {
        let inner: AsyncIterator<DownloadEvent> | null = null;
        let seq = 0;
        let sawStarted = false;
        const nextSeq = (): number => seq++;
        const ensureInner = async (): Promise<AsyncIterator<DownloadEvent>> => {
          if (!inner) {
            const model = await requireModel(id);
            inner = mapStream(downloadModelStream(model), (progress) =>
              toDownloadEvent(progress, model, id, nextSeq)
            )[Symbol.asyncIterator]();
          }
          return inner;
        };
        return {
          async next(): Promise<IteratorResult<DownloadEvent>> {
            if (!sawStarted) {
              sawStarted = true;
              await ensureInner();
              return { value: { type: 'started', operationId: id, sequence: nextSeq() }, done: false };
            }
            return (await ensureInner()).next();
          },
          async return(): Promise<IteratorResult<DownloadEvent>> {
            await inner?.return?.();
            return { value: undefined as unknown as DownloadEvent, done: true };
          },
        };
      },
    };
  },

  /**
   * Delete a downloaded model's files and clear its registry path.
   *
   * @throws SDKException when the delete could not be completed.
   */
  async delete(id: string): Promise<void> {
    const result = await deleteModel(id);
    if (result.error) {
      throw new SDKException(result.error);
    }
  },

  /**
   * Load a model now instead of paying for it on the first generation.
   *
   * Only `options.backendPreferences[0]` (equivalently the deprecated
   * `framework`) reaches commons today; `contextLength`, `threads`, and a
   * real `accelerator` choice are not yet carried by the native load ABI.
   *
   * @throws SDKException when the model is unknown, or `options` sets a
   * placement knob the load ABI cannot honor yet.
   */
  async load(id: string, options?: LoadOptions): Promise<LoadedModel> {
    const model = await requireModel(id);
    const unsupported = unsupportedLoadOptionKeys(options);
    if (unsupported.length > 0) {
      throw SDKException.invalidInput(
        `LoadOptions.${unsupported.join(', ')} cannot be carried by the native load ABI yet`
      );
    }
    const requestedBackend = resolvedBackendPreferences(options)[0];
    const result = await loadModel(
      ModelLoadRequest.fromPartial({
        modelId: id,
        category: model.category,
        ...(requestedBackend ? { framework: requestedBackend.backend } : {}),
        forceReload: options?.forceReload ?? false,
        validateAvailability: true,
      })
    );
    if (result.error) {
      throw new SDKException(result.error);
    }
    return {
      id,
      category: model.category,
      ...(requestedBackend ? { requestedBackend } : {}),
      actualBackend: requestedBackend?.backend ?? model.framework,
      actualDevice: 'unknown',
      async close(): Promise<void> {
        await models.unload(id);
      },
    };
  },

  /**
   * Release one resident model by `id`. Idempotent — a no-op when `id` is
   * not loaded.
   *
   * @throws SDKException when the unload fails.
   */
  async unload(id: string): Promise<void> {
    const model = await get(id);
    if (!model) return;
    const current = await modelInfoForCategory(model.category).catch(() => null);
    if (current?.id !== id) return;
    await unloadModel(
      ModelUnloadRequest.fromPartial({
        modelId: id,
        category: model.category,
        unloadAll: false,
      })
    );
  },

  /**
   * Unload the model resident under `category`, or every resident model
   * when `category` is omitted. This is the only category/global unload;
   * `unload` releases exactly one model by id.
   */
  async unloadAll(category?: ModelCategory): Promise<void> {
    await unloadModel(
      ModelUnloadRequest.fromPartial({
        unloadAll: category === undefined,
        ...(category !== undefined ? { category } : {}),
      })
    );
  },

  /**
   * Remove `id` from the registry. Registration metadata only — `id` must
   * already be unloaded and have no local artifacts.
   *
   * @throws SDKException when `id` is unknown, still loaded, or still has
   * local artifacts; call `unload`/`delete` first.
   */
  async unregister(id: string): Promise<void> {
    const model = await requireModel(id);
    const current = await modelInfoForCategory(model.category).catch(() => null);
    if (current?.id === id) {
      throw SDKException.invalidState(
        `Model '${id}' is currently loaded. Call models.unload('${id}') before unregister.`
      );
    }
    // `ModelInfo.isDownloaded` is deleted outright; `registryStatus` is the
    // single downloaded-ness signal now.
    if (
      model.registryStatus === ModelRegistryStatus.MODEL_REGISTRY_STATUS_DOWNLOADED ||
      model.registryStatus === ModelRegistryStatus.MODEL_REGISTRY_STATUS_LOADED ||
      model.localPath
    ) {
      throw SDKException.invalidState(
        `Model '${id}' still has local artifacts. Call models.delete('${id}') before unregister.`
      );
    }
    await removeModel(id);
  },

  /**
   * The model loaded for one category, or `null`.
   *
   * Outside the v3 spec: `state()` answers the same question but also walks
   * storage, which is too costly for UI that polls one category.
   */
  loaded(category: ModelCategory): Promise<ModelInfo | null> {
    return modelInfoForCategory(category);
  },

  /** What is loaded per category, plus the storage headroom left. */
  async state(): Promise<ModelsState> {
    const loaded: ModelsState['loaded'] = {};
    const snapshots = await Promise.all(
      CATEGORIES.map((category) =>
        modelInfoForCategory(category).catch(() => null)
      )
    );
    CATEGORIES.forEach((category, index) => {
      const model = snapshots[index];
      if (model) loaded[category] = model;
    });
    const storage = await getStorageInfo();
    return {
      loaded,
      storageUsedBytes: Number(storage?.app?.totalBytes ?? 0),
      storageFreeBytes: Number(storage?.device?.freeBytes ?? 0),
    };
  },

  /**
   * Rescan managed model directories and reconcile downloaded state.
   *
   * Matches `models.refresh` on the Swift, Kotlin, and Flutter namespaces,
   * including its defaults. Non-throwing like the others: a failed refresh
   * leaves the current registry contents in place.
   *
   * `list()` reads the registry as it stands and never rescans, so this is
   * the only way to pick up artifacts that changed on disk out from under
   * the SDK.
   */
  refresh(options?: {
    rescanLocal?: boolean;
    includeRemoteCatalog?: boolean;
    pruneOrphans?: boolean;
  }): Promise<void> {
    return refreshModelRegistry(options);
  },
};

/**
 * Make sure `modelId` is loaded for `category`, downloading it first when the
 * registry says it is not on disk yet. Generation verbs call this so callers
 * never have to pre-load.
 */
export async function ensureModelLoaded(
  modelId: string,
  category: ModelCategory
): Promise<void> {
  const current = await modelInfoForCategory(category).catch(() => null);
  if (current?.id === modelId) return;

  const model = await requireModel(modelId);
  const isDownloaded =
    model.registryStatus === ModelRegistryStatus.MODEL_REGISTRY_STATUS_DOWNLOADED ||
    model.registryStatus === ModelRegistryStatus.MODEL_REGISTRY_STATUS_LOADED;
  if (!isDownloaded) {
    const iterator = models.download(modelId)[Symbol.asyncIterator]();
    try {
      for (;;) {
        const step = await iterator.next();
        if (step.done) break;
      }
    } finally {
      await iterator.return?.();
    }
  }
  await models.load(modelId);
}

/**
 * Resolve the model id currently loaded for `category`.
 *
 * @throws SDKException when nothing is loaded for that category.
 */
export async function requireLoadedModelId(
  category: ModelCategory,
  operation: string
): Promise<string> {
  const model = await modelInfoForCategory(category).catch(() => null);
  if (!model?.id) {
    throw SDKException.of(
      ErrorCode.ERROR_CODE_MODEL_NOT_LOADED,
      `${operation} needs a loaded model; call RunAnywhere.models.load(id) first`
    );
  }
  return model.id;
}
