/**
 * `RunAnywhere.models` — catalog, downloads, and residency.
 */

import {
  ModelArtifactType,
  ModelCategory,
  ModelFileRole,
  type ModelInfo,
} from '@runanywhere/proto-ts/model_types';
import { DownloadState, type DownloadProgress } from '@runanywhere/proto-ts/download_service';
import { SDKException } from '../../../Foundation/SDKException.js';
import { Runtime } from '../../../Foundation/RuntimeConfig.js';
import { ModelRegistry } from '../../Extensions/RunAnywhere+ModelRegistry.js';
import { WebModelLifecycle } from '../../Extensions/RunAnywhere+ModelLifecycle.js';
import {
  registerModelArchive,
  registerModelFromUrl,
  registerModelMultiFile,
  type RegisterModelFile,
} from '../../Extensions/RunAnywhere+Storage.js';
import { SDKCore } from '../../SDKCore.js';
import type { LoadOptions, ModelFilter, ModelRegistration } from '../Options.js';
import type { DownloadEvent } from '../Events.js';
import type { ModelsState } from '../Results.js';
import { ensureReady } from '../Runtime/Prerequisites.js';

const FILE_ROLES = {
  primary: ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL,
  companion: ModelFileRole.MODEL_FILE_ROLE_COMPANION,
  projector: ModelFileRole.MODEL_FILE_ROLE_VISION_PROJECTOR,
  tokenizer: ModelFileRole.MODEL_FILE_ROLE_TOKENIZER,
  config: ModelFileRole.MODEL_FILE_ROLE_CONFIG,
  vocabulary: ModelFileRole.MODEL_FILE_ROLE_VOCABULARY,
  merges: ModelFileRole.MODEL_FILE_ROLE_MERGES,
  labels: ModelFileRole.MODEL_FILE_ROLE_LABELS,
} as const;

const ARCHIVE_TYPES = {
  tarGz: ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE,
  zip: ModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE,
} as const;

const LOADED_CATEGORIES: readonly ModelCategory[] = [
  ModelCategory.MODEL_CATEGORY_LANGUAGE,
  ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
  ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
  ModelCategory.MODEL_CATEGORY_VISION,
  ModelCategory.MODEL_CATEGORY_MULTIMODAL,
  ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION,
  ModelCategory.MODEL_CATEGORY_EMBEDDING,
  ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
  ModelCategory.MODEL_CATEGORY_SPEAKER_DIARIZATION,
  ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION,
];

function matchesFilter(model: ModelInfo, filter: ModelFilter): boolean {
  if (filter.category !== undefined && model.category !== filter.category) return false;
  if (filter.framework !== undefined && model.framework !== filter.framework) return false;
  if (filter.format !== undefined && model.format !== filter.format) return false;
  if (filter.downloadedOnly && !model.isDownloaded) return false;
  if (filter.availableOnly && !model.isAvailable) return false;
  if (filter.maxSizeBytes !== undefined && Number(model.downloadSizeBytes ?? 0) > filter.maxSizeBytes) {
    return false;
  }
  if (filter.search) {
    const needle = filter.search.toLowerCase();
    if (!model.id.toLowerCase().includes(needle) && !model.name.toLowerCase().includes(needle)) {
      return false;
    }
  }
  return true;
}

function toRegisterFiles(files: readonly NonNullable<ModelRegistration['files']>[number][]): RegisterModelFile[] {
  return files.map((file) => ({
    url: file.url,
    filename: file.filename,
    role: file.role
      ? FILE_ROLES[file.role]
      : ModelRegistry.inferModelFileRole(file.filename, ModelCategory.MODEL_CATEGORY_UNSPECIFIED),
    sizeBytes: file.sizeBytes ?? 0,
    isRequired: file.isRequired,
  }));
}

/** The model catalog and everything that governs residency. */
export const models = {
  /**
   * List catalog entries, optionally narrowed by a filter.
   *
   * @example
   * const chatModels = RunAnywhere.models.list({ category: ModelCategory.MODEL_CATEGORY_LANGUAGE });
   * console.log(chatModels.map((model) => model.id));
   */
  list(filter?: ModelFilter): ModelInfo[] {
    const all = ModelRegistry.listModels()?.models ?? [];
    return filter ? all.filter((model) => matchesFilter(model, filter)) : all;
  },

  /** One catalog entry, or `null` when the id is unknown. */
  get(id: string): ModelInfo | null {
    return ModelRegistry.getModel(id);
  },

  /**
   * Add a model to the catalog from a URL, an archive, or a multi-file manifest.
   *
   * @throws SDKException when neither `url` nor `files` is supplied.
   */
  register(model: ModelRegistration): ModelInfo {
    const shared = {
      id: model.id,
      description: model.description,
      format: model.format,
      modality: model.category,
      memoryRequirement: model.memoryRequiredBytes,
      downloadSizeBytes: model.sizeBytes,
      contextLength: model.contextLength,
      supportsThinking: model.supportsThinking,
      supportsLora: model.supportsLora,
      cuaProfile: model.cuaProfile,
    };
    if (model.files?.length) {
      return registerModelMultiFile({
        ...shared,
        id: model.id ?? model.name,
        name: model.name,
        framework: model.framework,
        files: toRegisterFiles(model.files),
      });
    }
    if (!model.url) {
      throw SDKException.invalidConfiguration(
        'models.register needs either a `url` or a `files` manifest.',
      );
    }
    if (model.archive) {
      return registerModelArchive(
        model.url,
        model.name,
        model.framework,
        ARCHIVE_TYPES[model.archive],
        shared,
      );
    }
    return registerModelFromUrl(model.url, model.name, model.framework, shared);
  },

  /**
   * Download a catalogued model, emitting progress until it completes.
   *
   * Breaking out of the iterator cancels the transfer and keeps its resume token.
   *
   * @throws SDKException when the id is unknown or storage is unavailable.
   */
  download(id: string): AsyncIterable<DownloadEvent> {
    return (async function* download(): AsyncGenerator<DownloadEvent> {
      await ensureReady();
      let sawExtracting = false;
      for await (const progress of SDKCore.downloadModelStream(id)) {
        if (progress.state === DownloadState.DOWNLOAD_STATE_EXTRACTING) {
          if (!sawExtracting) {
            sawExtracting = true;
            yield { type: 'extracting' };
          }
          continue;
        }
        if (progress.state === DownloadState.DOWNLOAD_STATE_COMPLETED) {
          const model = ModelRegistry.getModel(id);
          if (!model) {
            throw SDKException.processingFailed(
              `Download of '${id}' completed but the catalog entry disappeared.`,
            );
          }
          yield { type: 'completed', model };
          return;
        }
        yield toProgressEvent(progress);
      }
    })();
  },

  /** Remove a downloaded model's files and clear its registry path. */
  async delete(id: string): Promise<void> {
    await SDKCore.deleteModel(id);
  },

  /**
   * Load a model now instead of paying the cost on the first generation.
   *
   * @throws SDKException when the model is absent or the backend rejects it.
   */
  async load(id: string, options?: LoadOptions): Promise<void> {
    await ensureReady();
    if (options?.contextLength !== undefined || options?.threads !== undefined) {
      throw SDKException.invalidConfiguration(
        'contextLength and threads have no field on ModelLoadRequest in the IDL, so the Web SDK '
          + 'cannot honor them. Remove them or set them on the backend register() call.',
      );
    }
    if (options?.useGpu !== undefined) {
      await Runtime.setAcceleration(options.useGpu ? 'webgpu' : 'cpu');
    }
    const model = ModelRegistry.getModel(id);
    const result = await SDKCore.loadModel({
      modelId: id,
      category: model?.category,
      framework: options?.framework ?? model?.framework,
      forceReload: options?.forceReload ?? false,
      validateAvailability: true,
    });
    if (result?.error) {
      throw new SDKException(result.error);
    }
  },

  /** Unload one category's model, or every resident model when omitted. */
  async unload(category?: ModelCategory): Promise<void> {
    const result = await SDKCore.unloadModel({
      modelId: '',
      category,
      unloadAll: category === undefined,
    });
    if (result?.error) {
      throw new SDKException(result.error);
    }
  },

  /** What is resident right now, and how much storage remains. */
  async state(): Promise<ModelsState> {
    const loaded: ModelsState['loaded'] = {};
    for (const category of LOADED_CATEGORIES) {
      const current = WebModelLifecycle.currentModel({ category, includeModelMetadata: true });
      const model = current?.found ? current.model ?? ModelRegistry.getModel(current.modelId) : null;
      if (model) loaded[category] = model;
    }
    const estimate = typeof navigator !== 'undefined' && navigator.storage?.estimate
      ? await navigator.storage.estimate()
      : {};
    const quota = Number(estimate.quota ?? 0);
    const usage = Number(estimate.usage ?? 0);
    return {
      loaded,
      storageUsedBytes: usage,
      storageFreeBytes: Math.max(0, quota - usage),
    };
  },
};

function toProgressEvent(progress: DownloadProgress): DownloadEvent {
  const bytesTotal = Number(progress.totalBytes ?? 0);
  const bytesDone = Number(progress.bytesDownloaded ?? 0);
  return {
    type: 'progress',
    bytesDone,
    bytesTotal,
    percent: bytesTotal > 0 ? (bytesDone / bytesTotal) * 100 : progress.overallProgress * 100,
  };
}
