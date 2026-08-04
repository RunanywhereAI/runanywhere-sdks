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
  ModelUnloadRequest,
  type ModelInfo,
} from '@runanywhere/proto-ts/model_types';
import {
  DownloadStage,
  DownloadState,
} from '@runanywhere/proto-ts/download_service';

import { SDKException } from '../../Foundation/Errors/SDKException';
import { ErrorCategory, ErrorCode } from '@runanywhere/proto-ts/errors';
import type { SDKError } from '@runanywhere/proto-ts/errors';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import {
  downloadModelStream,
  getModel as getModelProto,
  listModels,
  queryModels,
  registerArchiveModel,
  registerModel as registerUrlModel,
  registerMultiFileModel,
} from '../Extensions/Models/RunAnywhere+ModelRegistry';
import {
  loadModel,
  modelInfoForCategory,
  unloadModel,
} from '../Extensions/Models/RunAnywhere+ModelLifecycle';
import { deleteModel } from '../Extensions/Storage/RunAnywhere+Storage';
import { getStorageInfo } from '../Extensions/Storage/RunAnywhere+Storage';
import { mapStream } from './Stream';
import type {
  DownloadEvent,
  LoadOptions,
  ModelFilter,
  ModelRegistration,
  ModelsState,
} from './Types';
import { ignoredLoadOptionKeys } from './LoadOptionsSupport';

const logger = new SDKLogger('RunAnywhere.models');

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

function toModelQuery(filter: ModelFilter): ModelQuery {
  return ModelQuery.fromPartial({
    ...(filter.category !== undefined ? { category: filter.category } : {}),
    ...(filter.framework !== undefined ? { framework: filter.framework } : {}),
    ...(filter.downloadedOnly !== undefined
      ? { downloadedOnly: filter.downloadedOnly }
      : {}),
    ...(filter.availableOnly !== undefined
      ? { availableOnly: filter.availableOnly }
      : {}),
    ...(filter.search ? { searchQuery: filter.search } : {}),
  });
}

function toDownloadEvent(
  progress: Parameters<typeof toDownloadEventInput>[0],
  model: ModelInfo
): DownloadEvent | undefined {
  return toDownloadEventInput(progress, model);
}

function toDownloadEventInput(
  progress: {
    stage: DownloadStage;
    state: DownloadState;
    bytesDownloaded: number;
    totalBytes: number;
    overallProgress: number;
    error?: SDKError | undefined;
  },
  model: ModelInfo
): DownloadEvent | undefined {
  if (progress.state === DownloadState.DOWNLOAD_STATE_FAILED) {
    throw progress.error
      ? new SDKException(progress.error)
      : SDKException.of(
          ErrorCode.ERROR_CODE_DOWNLOAD_FAILED,
          `download failed for ${model.id}`,
          { category: ErrorCategory.ERROR_CATEGORY_NETWORK }
        );
  }
  if (
    progress.state === DownloadState.DOWNLOAD_STATE_COMPLETED ||
    progress.stage === DownloadStage.DOWNLOAD_STAGE_COMPLETED
  ) {
    return { type: 'completed', model };
  }
  if (
    progress.stage === DownloadStage.DOWNLOAD_STAGE_EXTRACTING ||
    progress.state === DownloadState.DOWNLOAD_STATE_EXTRACTING
  ) {
    return { type: 'extracting' };
  }
  const bytesTotal = Number(progress.totalBytes);
  const bytesDone = Number(progress.bytesDownloaded);
  return {
    type: 'progress',
    bytesDone,
    bytesTotal,
    percent:
      progress.overallProgress > 0
        ? progress.overallProgress * 100
        : bytesTotal > 0
          ? (bytesDone / bytesTotal) * 100
          : 0,
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
        const ensureInner = async (): Promise<AsyncIterator<DownloadEvent>> => {
          if (!inner) {
            const model = await requireModel(id);
            inner = mapStream(downloadModelStream(model), (progress) =>
              toDownloadEvent(progress, model)
            )[Symbol.asyncIterator]();
          }
          return inner;
        };
        return {
          async next(): Promise<IteratorResult<DownloadEvent>> {
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
   * `options.contextLength`, `.threads`, and `.useGpu` are not carried by the
   * commons load ABI yet and are ignored; only `options.framework` reaches
   * commons today.
   *
   * @throws SDKException when the model is unknown or the load fails.
   */
  async load(id: string, options?: LoadOptions): Promise<void> {
    const model = await requireModel(id);
    const ignored = ignoredLoadOptionKeys(options);
    if (ignored.length > 0) {
      logger.warning(
        `LoadOptions ${ignored.join(', ')} are not carried by the commons load ABI yet`
      );
    }
    const result = await loadModel(
      ModelLoadRequest.fromPartial({
        modelId: id,
        category: model.category,
        ...(options?.framework !== undefined
          ? { framework: options.framework }
          : {}),
        validateAvailability: true,
      })
    );
    if (result.error) {
      throw new SDKException(result.error);
    }
  },

  /**
   * Unload one category's model, or everything when `category` is omitted.
   */
  async unload(category?: ModelCategory): Promise<void> {
    await unloadModel(
      ModelUnloadRequest.fromPartial({
        unloadAll: true,
        ...(category !== undefined ? { category } : {}),
      })
    );
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
  if (!model.isDownloaded) {
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
