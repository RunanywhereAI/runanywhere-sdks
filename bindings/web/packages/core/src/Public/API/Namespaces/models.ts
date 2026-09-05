/**
 * `RunAnywhere.models` — catalog, downloads, and residency.
 */

import {
  ModelArtifactType,
  ModelCategory,
  ModelCompatibilityRequest,
  ModelCompatibilityResult,
  ModelFileRole,
  type ModelLoadRequest,
  ModelRegistryStatus,
  type InferenceFramework,
  type ModelInfo,
} from '@runanywhere/proto-ts/model_types';
import { DownloadState, type DownloadProgress } from '@runanywhere/proto-ts/download_service';
import { SDKException } from '../../../Foundation/SDKException.js';
import { SDKLogger } from '../../../Foundation/SDKLogger.js';
import { Runtime } from '../../../Foundation/RuntimeConfig.js';
import { ModelRegistry } from '../../Extensions/RunAnywhere+ModelRegistry.js';
import { WebModelLifecycle } from '../../Extensions/RunAnywhere+ModelLifecycle.js';
import {
  registerModelArchive,
  registerModelFromUrl,
  registerModelMultiFile,
  type RegisterModelFile,
} from '../../Extensions/RunAnywhere+Storage.js';
import { DOWNLOAD_TRANSFER_FAILURE_RETRYABLE, SDKCore } from '../../SDKCore.js';
import type { AcceleratorPolicy, BackendPreference, LoadOptions, ModelFilter, ModelRegistration } from '../Options.js';
import { backendToFramework, frameworkToBackend } from '../Mapping.js';
import type { DownloadEvent } from '../Events.js';
import type { LoadedModel, ModelsState } from '../Results.js';
import { ensureReady } from '../Runtime/Prerequisites.js';
import { ProtoWasmBridge } from '../../../runtime/ProtoWasm.js';
import {
  getModuleForCapability,
  type EmscriptenRunanywhereModule,
} from '../../../runtime/EmscriptenModule.js';

const BYTES_PER_GIB = 1024 * 1024 * 1024;
const modelsLogger = new SDKLogger('models');

interface CompatibilityModule extends EmscriptenRunanywhereModule {
  _rac_model_compatibility_check_proto?(
    requestPtr: number,
    requestSize: number,
    outResult: number,
  ): number;
}

/** Browser-reported available RAM in bytes, or 0 when unknown (commons contract). */
function probeAvailableRamBytes(): number {
  if (typeof navigator === 'undefined') return 0;
  const deviceMemoryGiB = (navigator as Navigator & { deviceMemory?: number }).deviceMemory;
  if (typeof deviceMemoryGiB !== 'number' || !(deviceMemoryGiB > 0)) return 0;
  return Math.trunc(deviceMemoryGiB * BYTES_PER_GIB);
}

/** OPFS/quota free bytes when the browser reports them; else 0 (unknown). */
async function probeAvailableStorageBytes(): Promise<number> {
  if (typeof navigator === 'undefined' || !navigator.storage?.estimate) return 0;
  try {
    const estimate = await navigator.storage.estimate();
    const quota = Number(estimate.quota ?? 0);
    const usage = Number(estimate.usage ?? 0);
    if (!(quota > 0)) return 0;
    return Math.max(0, Math.trunc(quota - usage));
  } catch {
    return 0;
  }
}

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

/**
 * `ModelInfo.isDownloaded` was deleted outright; `registryStatus` is the sole
 * downloaded-ness signal (DOWNLOADED and LOADED both mean "on disk").
 */
function isDownloaded(model: ModelInfo): boolean {
  return model.registryStatus === ModelRegistryStatus.MODEL_REGISTRY_STATUS_DOWNLOADED
    || model.registryStatus === ModelRegistryStatus.MODEL_REGISTRY_STATUS_LOADED;
}

function matchesFilter(model: ModelInfo, filter: ModelFilter): boolean {
  if (filter.category !== undefined && model.category !== filter.category) return false;
  if (filter.framework !== undefined && model.framework !== filter.framework) return false;
  if (filter.format !== undefined && model.format !== filter.format) return false;
  if (filter.downloadedOnly && !isDownloaded(model)) return false;
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

interface ResolvedLoadOptions {
  requestedBackend?: BackendPreference;
  backendPreferences?: BackendPreference[];
  accelerator?: AcceleratorPolicy;
}

/** Fold the deprecated `framework`/`useGpu` aliases into their v4 replacements. */
function resolveLoadOptions(options?: LoadOptions): ResolvedLoadOptions {
  const backendPreferences = options?.backendPreferences?.length
    ? options.backendPreferences
    : options?.framework !== undefined
      ? [{ backend: frameworkToBackend(options.framework) }]
      : undefined;
  const accelerator = options?.accelerator
    ?? (options?.useGpu !== undefined ? (options.useGpu ? 'gpu' : 'cpu') : undefined);
  return {
    requestedBackend: backendPreferences?.[0],
    backendPreferences,
    accelerator,
  };
}

function validateLoadOptions(options?: LoadOptions): void {
  if (options?.threads !== undefined) {
    throw SDKException.invalidConfiguration(
      'LoadOptions.threads was retired from the load ABI (ModelLoadRequest reserved tag 7) '
        + 'and is not a hard runtime guarantee. Remove it.',
    );
  }
  if (options?.contextLength !== undefined
      && (!Number.isInteger(options.contextLength)
        || options.contextLength < 0
        || options.contextLength > 2_147_483_647)) {
    throw SDKException.invalidConfiguration(
      'LoadOptions.contextLength must be an integer between 0 and 2147483647.',
    );
  }
  if (options?.backendPreferences?.some((preference) => preference.required)) {
    throw SDKException.invalidConfiguration(
      'LoadOptions.backendPreferences.required cannot be carried by ModelLoadRequest because '
        + 'backend_preferences contains framework enums only. Remove required or pass one '
        + 'preferred backend.',
    );
  }
}

function makeModelLoadRequest(
  id: string,
  model: ModelInfo | null,
  options: LoadOptions | undefined,
  resolved: ResolvedLoadOptions,
): ModelLoadRequest {
  const framework = resolved.requestedBackend
    ? backendToFramework(resolved.requestedBackend.backend)
    : model?.framework;
  return {
    modelId: id,
    category: model?.category,
    framework,
    forceReload: options?.forceReload ?? false,
    validateAvailability: true,
    contextLength: options?.contextLength,
    backendPreferences: resolved.backendPreferences?.map(
      (preference) => backendToFramework(preference.backend),
    ) ?? [],
  };
}

/** True when `id` is resident under any category right now. */
function isModelResident(id: string): boolean {
  return LOADED_CATEGORIES.some((category) => {
    const current = WebModelLifecycle.currentModel({ category, includeModelMetadata: false });
    return current?.found && current.modelId === id;
  });
}

function toLoadedModel(
  id: string,
  category: ModelCategory,
  resolved: ResolvedLoadOptions,
  framework?: InferenceFramework,
): LoadedModel {
  return {
    id,
    category,
    requestedBackend: resolved.requestedBackend,
    actualBackend: frameworkToBackend(framework),
    actualDevice: Runtime.active === 'webgpu' ? 'gpu' : 'cpu',
    runtimeVersion: undefined,
    abiVersion: undefined,
    fallbackReason: Runtime.degradedReason ?? undefined,
    close(): Promise<void> {
      return models.unload(id);
    },
  };
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
   * Remove `id` from the catalog. Registration metadata only — artifacts and
   * residency must already be gone.
   *
   * @throws SDKException when the model is still loaded or still has local
   *   artifacts; call `models.unload`/`models.delete` first.
   */
  async unregister(id: string): Promise<void> {
    const model = ModelRegistry.getModel(id);
    if (!model) return;
    if (isModelResident(id)) {
      throw SDKException.invalidState(
        `Model '${id}' is currently loaded. Call models.unload('${id}') before unregister.`,
      );
    }
    if (isDownloaded(model) || model.localPath) {
      throw SDKException.invalidState(
        `Model '${id}' still has local artifacts. Call models.delete('${id}') before unregister.`,
      );
    }
    ModelRegistry.removeModel(id);
  },

  /**
   * Download a catalogued model, emitting progress correlated by `operationId`/`sequence`.
   *
   * Breaking out of the iterator cancels the transfer and keeps its resume token.
   *
   * @throws SDKException when the id is unknown or storage is unavailable.
   */
  download(id: string): AsyncIterable<DownloadEvent> {
    return (async function* download(): AsyncGenerator<DownloadEvent> {
      await ensureReady();
      const operationId = id;
      let sequence = 0;
      yield { type: 'started', operationId, sequence: sequence++ };
      let sawExtracting = false;
      for await (const progress of SDKCore.downloadModelStream(id)) {
        if (progress.state === DownloadState.DOWNLOAD_STATE_FAILED) {
          yield {
            type: 'failed',
            operationId,
            sequence: sequence++,
            error: {
              ...(progress.error ?? {
                category: 0,
                code: 0,
                message: `Download of '${id}' failed.`,
                timestampMs: Date.now(),
                severity: 0,
                component: 'storage',
                requestId: '',
              }),
              // The transfer had already started, so this is the resumable kind
              // of failure. Overrides whatever the commons error carries because
              // commons never fills that field in — see
              // DOWNLOAD_TRANSFER_FAILURE_RETRYABLE.
              retryable: DOWNLOAD_TRANSFER_FAILURE_RETRYABLE,
            },
          };
          return;
        }
        if (progress.state === DownloadState.DOWNLOAD_STATE_CANCELLED) {
          yield { type: 'cancelled', operationId, sequence: sequence++ };
          return;
        }
        if (progress.state === DownloadState.DOWNLOAD_STATE_EXTRACTING) {
          if (!sawExtracting) {
            sawExtracting = true;
            yield { type: 'extracting', operationId, sequence: sequence++ };
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
          yield { type: 'completed', operationId, sequence: sequence++, modelId: id };
          return;
        }
        yield toProgressEvent(progress, operationId, sequence++);
      }
    })();
  },

  /** Remove a downloaded model's files and clear its registry path. */
  async delete(id: string): Promise<void> {
    await SDKCore.deleteModel(id);
  },

  /**
   * Load a model now instead of paying the cost on the first generation.
   * contextLength and optional backendPreferences are forwarded on ModelLoadRequest.
   * @throws SDKException when the model is absent; accelerator npu, threads, an invalid
   *   context length, or a required backend preference is requested; or the backend rejects
   *   the load.
   */
  async load(id: string, options?: LoadOptions): Promise<LoadedModel> {
    await ensureReady();
    validateLoadOptions(options);
    if (options?.accelerator === 'npu') {
      throw SDKException.unsupportedCapability(
        'LoadOptions.accelerator = npu',
        'The Web SDK has no NPU access from the browser; use "auto", "cpu", or "gpu".',
      );
    }
    const resolved = resolveLoadOptions(options);
    if (resolved.accelerator && resolved.accelerator !== 'auto') {
      await Runtime.setAcceleration(resolved.accelerator === 'gpu' ? 'webgpu' : 'cpu');
    }
    const model = ModelRegistry.getModel(id);
    const result = await SDKCore.loadModel(makeModelLoadRequest(id, model, options, resolved));
    if (!result || result.error) {
      throw result?.error
        ? new SDKException(result.error)
        : SDKException.processingFailed(`Loading '${id}' failed.`);
    }
    return toLoadedModel(id, result.category, resolved, result.framework);
  },

  /**
   * Release one resident model. Idempotent — a no-op when `id` is not loaded.
   */
  async unload(id: string): Promise<void> {
    const model = ModelRegistry.getModel(id);
    const result = await SDKCore.unloadModel({
      modelId: id,
      category: model?.category,
      unloadAll: false,
    });
    if (result?.error) {
      throw new SDKException(result.error);
    }
  },

  /** Unload one category's resident model, or every resident model when omitted. */
  async unloadAll(category?: ModelCategory): Promise<void> {
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

  /**
   * Evaluate one registered model against available RAM / free storage.
   * Verdict (`canRun` / `canFit` / `isCompatible`) is owned by commons.
   *
   * Pass a model id for the default probe, or a full
   * {@link ModelCompatibilityRequest} when the caller already measured
   * available bytes. Missing WASM export or a native failure throws
   * `SDKException` — callers must not invent a local budget substitute.
   */
  async checkCompatibility(
    idOrRequest: string | ModelCompatibilityRequest,
  ): Promise<ModelCompatibilityResult> {
    await ensureReady();
    const module = getModuleForCapability('commons') as CompatibilityModule | null;
    if (!module || typeof module._rac_model_compatibility_check_proto !== 'function') {
      throw SDKException.backendNotAvailable(
        'models.checkCompatibility',
        'Loaded WASM module does not export _rac_model_compatibility_check_proto. Rebuild the commons WASM.',
      );
    }

    const request: ModelCompatibilityRequest = typeof idOrRequest === 'string'
      ? ModelCompatibilityRequest.fromPartial({
          modelId: idOrRequest,
          availableRamBytes: probeAvailableRamBytes(),
          availableStorageBytes: await probeAvailableStorageBytes(),
        })
      : ModelCompatibilityRequest.fromPartial({
          modelId: idOrRequest.modelId,
          availableRamBytes: idOrRequest.availableRamBytes,
          availableStorageBytes: idOrRequest.availableStorageBytes,
          acceleratorPreference: idOrRequest.acceleratorPreference,
          preferredFramework: idOrRequest.preferredFramework,
        });

    if (!request.modelId) {
      throw SDKException.validationFailed({
        fieldPath: 'modelId',
        message: 'models.checkCompatibility requires a model id',
      });
    }

    const result = new ProtoWasmBridge(module, modelsLogger).withEncodedRequest(
      request,
      ModelCompatibilityRequest,
      ModelCompatibilityResult,
      (requestPtr, requestSize, outResult) => (
        module._rac_model_compatibility_check_proto!(requestPtr, requestSize, outResult)
      ),
      'rac_model_compatibility_check_proto',
    );
    if (!result) {
      throw SDKException.backendNotAvailable(
        'models.checkCompatibility',
        'rac_model_compatibility_check_proto returned no result',
      );
    }
    if (result.error) throw new SDKException(result.error);
    return result;
  },
};

/**
 * Map a commons `DownloadProgress` onto the public progress event.
 *
 * C++ reports 0 for "not measured yet" on throughput / overall fraction, and
 * leaves `eta_seconds` absent (or negative) for unknown. Those sentinels become
 * `undefined` here so a UI can omit "0 B/s" while the transfer spins up — same
 * normalisation as Kotlin / Swift. Callers must not re-derive rate, ETA, or
 * overall fraction from successive byte counts.
 */
function toProgressEvent(progress: DownloadProgress, operationId: string, sequence: number): DownloadEvent {
  const bytesTotal = Number(progress.totalBytes ?? 0);
  const bytesDone = Number(progress.bytesDownloaded ?? 0);
  const bytesPerSecond = progress.bytesPerSecond > 0 ? progress.bytesPerSecond : undefined;
  const etaSeconds =
    progress.etaSeconds !== undefined && progress.etaSeconds >= 0
      ? Number(progress.etaSeconds)
      : undefined;
  const overallProgress = progress.overallProgress > 0 ? progress.overallProgress : undefined;
  return {
    type: 'progress',
    operationId,
    sequence,
    bytesDone,
    bytesTotal,
    file: progress.currentFileName || undefined,
    bytesPerSecond,
    etaSeconds,
    retryAttempt: progress.retryAttempt ?? 0,
    overallProgress,
    currentFileIndex: progress.currentFileIndex ?? 0,
    totalFiles: Math.max(progress.totalFiles ?? 1, 1),
  };
}

/** Test seam for request construction and download progress mapping. */
export const __testing__ = {
  makeModelLoadRequest,
  resolveLoadOptions,
  toProgressEvent,
  validateLoadOptions,
};
