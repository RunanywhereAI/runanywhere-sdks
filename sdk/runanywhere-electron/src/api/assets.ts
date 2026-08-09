// assets.ts — the `models`, `lora`, `images`, and `segmentation` namespaces.

import { isCatalogId } from '../catalog';
import { ErrorCode, SDKException } from '../errors';
import { dropDownloadTask, notify, putDownloadTask, readDownloadTasks } from '../download';
import {
  DownloadCancelRequest,
  DownloadPlanRequest,
  DownloadProgress,
  DownloadStartRequest,
  DownloadState,
  DownloadSubscribeRequest,
} from '../proto/download_service';
import { DownloadAbi, isTerminalState, percentOf } from './download-abi';
import type { LoadSlot, RaBackend } from './backend';
import type { SdkEventHub } from './hub';
import { bridgeStream } from './iter';
import {
  ModelAbi,
  categoryFromProto,
  categoryToProto,
  frameworkFromProto,
  frameworkToProto,
  toPublicModelInfo,
} from './model-abi';
import { IMAGE_DEFAULTS, SEGMENTATION_DEFAULTS } from './options';
import type { ImageOptions, LoadOptions, SegmentationOptions } from './options';
import { DataAbi, toClassMask, toSegmentationRequest } from './data-abi';
import { LoraAbi } from './lora-abi';
import { ResidencyPolicy } from './residency';
import type { ResidentModel } from './residency';
import {
  ModelFileRole,
  ModelFormat,
  ModelRegistryStatus,
  ModelSource,
  ModelInfo as ProtoModelInfo,
} from '../proto/model_types';
import type { ModelLoadResult } from '../proto/model_types';
import { DevicePlacement, InferenceFramework, ModelCategory, requireOneOf } from './types';
import type {
  DownloadEvent,
  ImageEvent,
  ImageInput,
  ImageResult,
  LoadedModel,
  LoraState,
  ModelFilter,
  ModelInfo,
  ModelRegistration,
  ModelsState,
  SegmentationResult,
} from './types';

/** What the asset namespaces need from the facade. */
export interface AssetDeps {
  backend: RaBackend;
  hub: SdkEventHub;
  requireReady(): void;
  /** Where the SDK was initialized, read late because it is set by `initialize`. */
  baseDir?(): string | undefined;
}

const SLOT_OF_CATEGORY: Partial<Record<ModelCategory, LoadSlot>> = {
  [ModelCategory.LANGUAGE]: 'llm',
  [ModelCategory.VISION]: 'vlm',
  [ModelCategory.EMBEDDING]: 'embedder',
  [ModelCategory.SPEECH_TO_TEXT]: 'stt',
  [ModelCategory.TEXT_TO_SPEECH]: 'tts',
  [ModelCategory.RERANK]: 'rerank',
  [ModelCategory.DIARIZATION]: 'diarization',
  [ModelCategory.SEGMENTATION]: 'segmentation',
};

/**
 * Categories whose model lives in commons' lifecycle store rather than an addon
 * slot, because that is where their proto entry points read it from. Each
 * feature migration adds its category here; the rest stay component handles
 * until their own feature lands.
 */
const LIFECYCLE_CATEGORIES: ReadonlySet<ModelCategory> = new Set([
  ModelCategory.LANGUAGE,
  ModelCategory.VISION,
  ModelCategory.SPEECH_TO_TEXT,
  ModelCategory.TEXT_TO_SPEECH,
  ModelCategory.EMBEDDING,
  ModelCategory.DIARIZATION,
  ModelCategory.SEGMENTATION,
  // RERANK is deliberately absent: rac_rerank_component_rerank_proto is the
  // only rerank entry point commons exposes and it takes a component handle,
  // so the reranker stays in an addon slot.
]);

const FORMAT_OF_CATEGORY: Partial<Record<ModelCategory, ModelFormat>> = {
  [ModelCategory.LANGUAGE]: ModelFormat.MODEL_FORMAT_GGUF,
  [ModelCategory.VISION]: ModelFormat.MODEL_FORMAT_GGUF,
  [ModelCategory.EMBEDDING]: ModelFormat.MODEL_FORMAT_ONNX,
  [ModelCategory.RERANK]: ModelFormat.MODEL_FORMAT_GGUF,
  [ModelCategory.SPEECH_TO_TEXT]: ModelFormat.MODEL_FORMAT_FOLDER,
  [ModelCategory.TEXT_TO_SPEECH]: ModelFormat.MODEL_FORMAT_FOLDER,
};

/** What {@link ModelsNamespace.refresh} should reconcile. */
export interface RefreshOptions {
  /** Merge a remote catalog through the control plane. Off by default. */
  includeRemoteCatalog?: boolean;
  /** Rescan the model store for artifacts on disk. On by default. */
  rescanLocal?: boolean;
  /** Clear downloaded state for rows whose files are gone. On by default. */
  pruneOrphans?: boolean;
}

/** Model discovery, download, and placement. */
export interface ModelsNamespace {
  /**
   * List the models the SDK knows about.
   *
   * @example
   * const llms = await RunAnywhere.models.list({ category: 'LANGUAGE' });
   * console.log(llms.map((m) => m.id));
   */
  list(filter?: ModelFilter): Promise<ModelInfo[]>;
  /** One model by id, or null when it is unknown. */
  get(id: string): Promise<ModelInfo | null>;
  /** Add a model — a URL, an archive, several files, or a local path. */
  register(model: ModelRegistration): Promise<ModelInfo>;
  /**
   * Drop a model's registry row, leaving its files alone. The inverse of
   * {@link register}; {@link delete} is what frees disk.
   */
  unregister(id: string): Promise<void>;
  /**
   * Re-read the registry: rescan the model store for artifacts that arrived or
   * vanished outside the SDK, and clear the downloaded flag on rows whose files
   * are gone.
   */
  refresh(options?: RefreshOptions): Promise<ModelInfo[]>;
  /**
   * Fetch a model, reporting progress and completion in one stream.
   *
   * The transfer runs in commons, so it survives the consumer walking away from
   * the iterator; use {@link cancel} to actually stop it. Calling `download`
   * again for a model already in flight joins that transfer rather than starting
   * a second one.
   */
  download(id: string): AsyncIterableIterator<DownloadEvent>;
  /**
   * Stop a running download but keep the bytes already on disk, so a later
   * {@link download} or {@link resume} continues instead of refetching.
   */
  pause(id: string): Promise<void>;
  /**
   * Restart a paused or interrupted download from the bytes on disk. Equivalent
   * to `download(id)` — commons has no separate resume verb — but it does not
   * return a stream, so it is the right call for resuming at startup.
   */
  resume(id: string): Promise<void>;
  /** Stop a download and discard its partial bytes. */
  cancel(id: string): Promise<void>;
  /** Models this machine left mid-download, from the persisted task table. */
  interrupted(): Promise<string[]>;
  /** Remove a model's files from the store. */
  delete(id: string): Promise<void>;
  /**
   * Load a model into residency now, returning an ownership handle.
   *
   * @throws SDKException when the id/category is unknown or the load fails.
   * @example
   * const model = await RunAnywhere.models.load('qwen3.5-0.8b');
   * console.log(model.actualBackend);
   * await model.close();
   */
  load(id: string, options?: LoadOptions): Promise<LoadedModel>;
  /** Release one resident model. Idempotent — a no-op when `id` is not loaded. */
  unload(id: string): Promise<void>;
  /** Release one category's resident model, or every resident model when omitted. */
  unloadAll(category?: ModelCategory): Promise<void>;
  /** What is loaded and how much storage is left. */
  state(): Promise<ModelsState>;
}

/**
 * Build a `LoadedModel` handle from what commons reported. `actualBackend` is
 * the registry's framework for the row rather than an echo of the request, and
 * `actualDevice` mirrors `LoadOptions.useGpu` because the component load path
 * does not report placement. The lifecycle path does, through
 * {@link toLifecycleLoadedModel}.
 */
function toLoadedModel(
  id: string,
  category: ModelCategory,
  framework: InferenceFramework | undefined,
  options: LoadOptions,
  unload: (id: string) => Promise<void>
): LoadedModel {
  return {
    id,
    category,
    requestedBackend: options.framework,
    actualBackend: options.framework ?? framework,
    actualDevice: options.useGpu ? DevicePlacement.GPU : DevicePlacement.CPU,
    close: () => unload(id),
  };
}

// `actual_device_kind` is a free-form runtime string (cpu | gpu | npu | metal |
// webgpu | unknown); anything that is not plainly a CPU load counts as
// accelerated, since Metal and NPU are both "not the CPU" to a caller.
function toDevicePlacement(kind: string | undefined, requestedGpu: boolean): DevicePlacement {
  if (!kind || kind === 'unknown') return requestedGpu ? DevicePlacement.GPU : DevicePlacement.CPU;
  return kind === 'cpu' ? DevicePlacement.CPU : DevicePlacement.GPU;
}

/** A `LoadedModel` built from what the lifecycle load actually did. */
function toLifecycleLoadedModel(
  result: ModelLoadResult,
  category: ModelCategory,
  options: LoadOptions,
  unload: (id: string) => Promise<void>
): LoadedModel {
  return {
    id: result.modelId,
    category,
    requestedBackend: options.framework,
    actualBackend: frameworkFromProto(result.framework) ?? options.framework,
    actualDevice: toDevicePlacement(result.actualDeviceKind, options.useGpu ?? false),
    close: () => unload(result.modelId),
  };
}

/**
 * Fan-out for the one download progress callback commons offers.
 *
 * `rac_download_set_progress_proto_callback` is process-wide: every task reports
 * through the same pointer, so the subscription opens once and each caller
 * filters by model id. It closes again when the last follower finishes, which is
 * what lets a process with no downloads exit.
 *
 * The poll is a safety net rather than the mechanism. A small file can reach
 * COMPLETED before the caller has registered its listener, and nothing replays
 * missed callbacks, so the terminal state is also read from
 * `rac_download_progress_poll_proto` on a timer.
 */
class DownloadWatcher {
  private readonly followers = new Map<string, (progress: DownloadProgress) => void>();
  private open: Promise<void> | null = null;

  constructor(private readonly backend: RaBackend) {}

  follow(
    modelId: string,
    onProgress: (progress: DownloadProgress) => void,
    poll: () => Promise<DownloadProgress>
  ): Promise<void> {
    if (!this.open) {
      this.open = this.backend.downloadWatch((bytes) => {
        const progress = DownloadProgress.decode(bytes);
        this.followers.get(progress.modelId)?.(progress);
      });
      this.open.catch(() => undefined);
    }
    return new Promise<void>((resolve) => {
      let settled = false;
      const finish = (): void => {
        if (settled) return;
        settled = true;
        clearInterval(timer);
        this.followers.delete(modelId);
        if (this.followers.size === 0) {
          this.open = null;
          void this.backend.downloadUnwatch();
        }
        resolve();
      };
      const handle = (progress: DownloadProgress): void => {
        if (settled) return;
        onProgress(progress);
        if (isTerminalState(progress.state)) finish();
      };
      this.followers.set(modelId, handle);
      const timer = setInterval(() => {
        poll().then(
          (progress) => {
            if (!settled && isTerminalState(progress.state)) handle(progress);
          },
          () => undefined
        );
      }, 250);
      timer.unref?.();
    });
  }
}

/** Build the `models` namespace over the commons registry. */
export function createModelsNamespace(deps: AssetDeps): ModelsNamespace {
  const abi = new ModelAbi(deps.backend);
  const downloads = new DownloadAbi(deps.backend);
  const watcher = new DownloadWatcher(deps.backend);
  const baseDir = (): string | undefined => deps.baseDir?.();

  // What commons currently holds for a lifecycle-backed category. The category
  // filter is what keeps a resident VLM from answering "which language model is
  // loaded" and vice versa.
  const residentLifecycleModel = async (category: ModelCategory): Promise<string | null> => {
    const current = await abi.current({
      category: categoryToProto(category),
      includeModelMetadata: false,
    });
    return current.found && current.modelId ? current.modelId : null;
  };

  const unloadLifecycleModel = async (category: ModelCategory): Promise<string | null> => {
    const id = await residentLifecycleModel(category);
    if (!id) return null;
    const result = await abi.unload({ modelId: id, unloadAll: false });
    if (result.error) throw SDKException.fromProto(result.error);
    return id;
  };

  // What the residency policy sees, expressed as categories so it never has to
  // know which store a category lives in.
  const residency = new ResidencyPolicy(deps.backend, abi, {
    async resident() {
      const entries = await Promise.all(
        (Object.entries(SLOT_OF_CATEGORY) as Array<[ModelCategory, LoadSlot]>).map(
          async ([category, slot]) => {
            const id = LIFECYCLE_CATEGORIES.has(category)
              ? await residentLifecycleModel(category)
              : (await deps.backend.loaded(slot))?.id ?? null;
            return id ? { category, id } : null;
          }
        )
      );
      return entries.filter((e): e is ResidentModel => e !== null);
    },
    async release(model) {
      if (LIFECYCLE_CATEGORIES.has(model.category)) {
        await unloadLifecycleModel(model.category);
        deps.hub.emit({ type: 'modelUnloaded', id: model.id });
        return;
      }
      const slot = SLOT_OF_CATEGORY[model.category];
      if (!slot) return;
      await deps.backend.unload(slot);
      deps.hub.emit({ type: 'modelUnloaded', id: model.id });
    },
  });

  const rowFor = (id: string): Promise<ProtoModelInfo | null> => abi.get(id);

  const infoFor = async (id: string): Promise<ModelInfo | null> => {
    const row = await rowFor(id);
    return row ? toPublicModelInfo(row) : null;
  };

  const slotFor = (category: ModelCategory): LoadSlot => {
    const slot = SLOT_OF_CATEGORY[category];
    if (!slot) {
      throw SDKException.notImplemented(`loading ${category} models on Electron`);
    }
    return slot;
  };

  const categoryOf = async (id: string): Promise<ModelCategory> => {
    const row = await rowFor(id);
    const category = row ? categoryFromProto(row.category) : undefined;
    if (!category) throw SDKException.modelNotFound(id);
    return category;
  };

  const sourceFor = (registration: ModelRegistration): string => {
    if (registration.path) return registration.path;
    if (registration.url) return registration.url;
    if (registration.files?.length) return registration.files[0].url;
    throw SDKException.validationFailed({
      fieldPath: 'model',
      message: 'a registration needs a path, a url, or files',
    });
  };

  // What `backend.ensure` downloads and loads. A catalog id keeps resolving
  // through the staged table until the download stack moves onto the commons
  // orchestrator; anything else resolves through its registry row, and an
  // unregistered id is passed through as a directly loadable source (an HF repo,
  // a URL, or a path).
  const resolveSource = async (id: string): Promise<string> => {
    if (isCatalogId(id)) return id;
    const row = await rowFor(id);
    if (!row) return id;
    return row.localPath || row.downloadUrl || id;
  };

  const api: ModelsNamespace = {
    async list(filter = {}) {
      const rows = await abi.list({
        category: filter.category ? categoryToProto(filter.category) : undefined,
        downloadedOnly: filter.downloadedOnly ?? undefined,
      });
      return rows.map(toPublicModelInfo);
    },

    get(id) {
      return infoFor(id);
    },

    async register(model) {
      requireOneOf(model, ['url', 'files', 'path'], 'model');
      if (!model.category) {
        throw SDKException.validationFailed({
          fieldPath: 'model.category',
          message: 'a registration needs a category',
        });
      }
      const category = categoryToProto(model.category);
      const framework = model.framework ? frameworkToProto(model.framework) : undefined;
      const id = model.id ?? sourceFor(model);

      // Several files that make up one model go through the multi-file factory so
      // commons owns the descriptor roles the artifact resolver later matches on.
      if (model.files?.length) {
        const saved = await abi.registerMultiFile({
          id,
          name: model.name ?? id,
          framework: framework ?? frameworkToProto(InferenceFramework.ONNX),
          category,
          format: FORMAT_OF_CATEGORY[model.category],
          files: model.files.map((f, index) => ({
            url: f.url,
            filename: f.as,
            isOptional: false,
            relativePath: f.as,
            role:
              index === 0
                ? ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL
                : ModelFileRole.MODEL_FILE_ROLE_COMPANION,
          })),
        });
        return toPublicModelInfo(saved);
      }

      const saved = await abi.registerFromUrl({
        url: model.path ?? model.url ?? '',
        name: model.name ?? id,
        id,
        framework,
        category,
        source: model.path ? ModelSource.MODEL_SOURCE_LOCAL : ModelSource.MODEL_SOURCE_REMOTE,
      });
      return toPublicModelInfo(saved);
    },

    async unregister(id) {
      await abi.remove(id);
    },

    async refresh(options = {}) {
      const result = await abi.refresh({
        includeRemoteCatalog: options.includeRemoteCatalog ?? false,
        rescanLocal: options.rescanLocal ?? true,
        pruneOrphans: options.pruneOrphans ?? true,
        catalogUri: '',
        forceRefresh: false,
        includeDownloadedState: true,
      });
      if (result.error) throw SDKException.fromProto(result.error);
      return (result.models?.models ?? []).map(toPublicModelInfo);
    },

    download(id) {
      return bridgeStream<DownloadEvent>(async (sink) => {
        // Already here: commons plans a fresh transfer into its own model folder
        // and has no "this is already downloaded" short circuit, so asking it
        // would refetch a model the caller can already load.
        const present = await rowFor(id);
        if (present?.localPath && (await deps.backend.pathExists(present.localPath))) {
          sink.push({ type: 'completed', model: toPublicModelInfo(present) });
          return;
        }
        const started = await startDownload(id);
        let extracting = false;
        let last: DownloadProgress | null = null;
        const poll = (): Promise<DownloadProgress> =>
          downloads.poll(
            DownloadSubscribeRequest.fromPartial({ modelId: id, taskId: started.taskId })
          );
        await watcher.follow(id, (progress) => {
          last = progress;
          // Only a live transfer belongs in the table. A terminal state's
          // bookkeeping is owned by whoever caused it — pause keeps the row,
          // cancel and completion drop it — so writing here would race them.
          if (!isTerminalState(progress.state)) {
            putDownloadTask(
              {
                modelId: id,
                taskId: progress.taskId || started.taskId,
                paused: false,
                bytesDownloaded: Number(progress.bytesDownloaded),
                totalBytes: Number(progress.totalBytes),
                updatedAtUnixMs: Date.now(),
              },
              baseDir()
            );
          }
          if (progress.state === DownloadState.DOWNLOAD_STATE_EXTRACTING) {
            // Extraction reports its own stage progress, but a UI only needs to
            // be told once that the bytes are in and the archive is unpacking.
            if (!extracting) {
              extracting = true;
              sink.push({ type: 'extracting' });
            }
            return;
          }
          sink.push({
            type: 'progress',
            bytesDone: Number(progress.bytesDownloaded),
            bytesTotal: Number(progress.totalBytes),
            percent: percentOf(progress),
          });
        }, poll);
        const terminal = last as DownloadProgress | null;
        await downloads.cleanup();
        if (terminal?.state === DownloadState.DOWNLOAD_STATE_FAILED) {
          dropDownloadTask(id, baseDir());
          notify('Download failed', `${id}: ${terminal.error?.message ?? 'unknown error'}`);
          throw terminal.error
            ? SDKException.fromProto(terminal.error)
            : SDKException.of(ErrorCode.STORAGE_ERROR, `download failed for ${id}`);
        }
        if (terminal?.state === DownloadState.DOWNLOAD_STATE_CANCELLED) {
          return; // pause() and cancel() own the bookkeeping; just end the stream
        }
        dropDownloadTask(id, baseDir());
        const info = await markDownloaded(id, terminal?.localPath ?? '');
        notify('Download complete', info.name || id);
        sink.push({ type: 'completed', model: info });
      });
    },

    async pause(id) {
      const result = await downloads.cancel(
        DownloadCancelRequest.fromPartial({ modelId: id, deletePartialBytes: false })
      );
      if (result.error) throw SDKException.fromProto(result.error);
      const existing = readDownloadTasks(baseDir()).find((t) => t.modelId === id);
      putDownloadTask(
        {
          modelId: id,
          taskId: result.taskId || existing?.taskId || '',
          paused: true,
          bytesDownloaded: existing?.bytesDownloaded ?? 0,
          totalBytes: existing?.totalBytes ?? 0,
          updatedAtUnixMs: Date.now(),
        },
        baseDir()
      );
    },

    async resume(id) {
      await startDownload(id);
    },

    async cancel(id) {
      const result = await downloads.cancel(
        DownloadCancelRequest.fromPartial({ modelId: id, deletePartialBytes: true })
      );
      if (result.error) throw SDKException.fromProto(result.error);
      dropDownloadTask(id, baseDir());
      await downloads.cleanup();
    },

    async interrupted() {
      return readDownloadTasks(baseDir()).map((t) => t.modelId);
    },

    async delete(id) {
      const category = await categoryOf(id).catch(() => null);
      // Deleting the files under a resident model would leave the engine reading
      // a path that no longer exists, so release it first.
      if (category && LIFECYCLE_CATEGORIES.has(category)) {
        if ((await residentLifecycleModel(category)) === id) await unloadLifecycleModel(category);
      } else if (category) {
        const slot = SLOT_OF_CATEGORY[category];
        const loaded = slot ? await deps.backend.loaded(slot) : null;
        if (slot && loaded && loaded.id === id) await deps.backend.unload(slot);
      }
      const row = await rowFor(id);
      await deps.backend.deleteModel(id);
      // commons removes `{base}/RunAnywhere/Models/{framework}/{id}/`, which is
      // where it puts everything it downloads. A row whose files predate that —
      // seeded from a catalog that wrote them somewhere else — is reported here
      // rather than silently left on disk with its registry entry gone.
      if (row?.localPath && (await deps.backend.pathExists(row.localPath))) {
        throw SDKException.of(
          ErrorCode.STORAGE_ERROR,
          `commons deleted the model store folder for ${id} but ${row.localPath} is still on ` +
            'disk: this row points outside the commons model store, so its files have to be ' +
            'removed by whatever put them there'
        );
      }
      await abi.remove(id).catch(() => undefined);
      dropDownloadTask(id, baseDir());
      deps.hub.emit({ type: 'modelUnloaded', id });
    },

    async load(id, options = {}) {
      deps.requireReady();
      const row = await rowFor(id);
      const category = row ? categoryFromProto(row.category) : undefined;
      if (!category) throw SDKException.modelNotFound(id);
      const slot = slotFor(category);
      // Make room before the load rather than after the machine is already out
      // of memory. Nothing is released while commons says the model fits.
      const decision = await residency.admit(id, category, options.keepResident ?? []);
      if (!decision.fits) {
        deps.hub.emit({
          type: 'memoryPressure',
          id,
          requiredBytes: decision.requiredBytes,
          availableBytes: decision.availableBytes,
          evicted: decision.evicted.map((m) => m.id),
          reasons: decision.reasons,
        });
      }

      if (LIFECYCLE_CATEGORIES.has(category)) {
        // Commons resolves the artifact from the registry row, so the file has
        // to be on disk and the row has to point at it before the load. A VLM's
        // projector rides along in the row's VISION_PROJECTOR file descriptor,
        // which is what commons' resolver matches on.
        const resolved = await deps.backend.resolveModel(await resolveSource(id));
        await markDownloaded(id, resolved.primary);
        const result = await abi.load({
          modelId: id,
          category: categoryToProto(category),
          forceReload: false,
          validateAvailability: true,
          backendPreferences: options.framework ? [frameworkToProto(options.framework)] : [],
          contextLength: options.contextLength,
          useGpu: options.useGpu,
        });
        if (result.error) throw SDKException.fromProto(result.error);
        const model = toLifecycleLoadedModel(result, category, options, api.unload);
        deps.hub.emit({
          type: 'modelLoaded',
          id: model.id,
          category,
          actualBackend: model.actualBackend,
        });
        return model;
      }

      const loaded = await deps.backend.ensure(slot, await resolveSource(id), {
        framework: options.framework,
        contextLength: options.contextLength,
        threads: options.threads,
        useGpu: options.useGpu,
      });
      await markDownloaded(id, loaded.path);
      const model = toLoadedModel(
        loaded.id,
        category,
        row ? frameworkFromProto(row.framework) : undefined,
        options,
        api.unload
      );
      deps.hub.emit({ type: 'modelLoaded', id: loaded.id, category, actualBackend: model.actualBackend });
      return model;
    },

    async unload(id) {
      deps.requireReady();
      const category = await categoryOf(id).catch(() => null);
      if (!category) return;
      if (LIFECYCLE_CATEGORIES.has(category)) {
        if ((await residentLifecycleModel(category)) !== id) return;
        await unloadLifecycleModel(category);
        deps.hub.emit({ type: 'modelUnloaded', id });
        return;
      }
      const slot = SLOT_OF_CATEGORY[category];
      if (!slot) return;
      const loaded = await deps.backend.loaded(slot);
      if (!loaded || loaded.id !== id) return;
      await deps.backend.unload(slot);
      deps.hub.emit({ type: 'modelUnloaded', id });
    },

    async unloadAll(category) {
      if (!category) {
        const previous = await Promise.all(
          Object.values(SLOT_OF_CATEGORY).map((slot) => deps.backend.loaded(slot as LoadSlot))
        );
        const lifecycle = await Promise.all(
          [...LIFECYCLE_CATEGORIES].map((c) => unloadLifecycleModel(c))
        );
        await deps.backend.unload();
        for (const id of lifecycle) if (id) deps.hub.emit({ type: 'modelUnloaded', id });
        for (const p of previous) if (p) deps.hub.emit({ type: 'modelUnloaded', id: p.id });
        return;
      }
      if (LIFECYCLE_CATEGORIES.has(category)) {
        const released = await unloadLifecycleModel(category);
        if (released) deps.hub.emit({ type: 'modelUnloaded', id: released });
        return;
      }
      const slot = slotFor(category);
      const loaded = await deps.backend.loaded(slot);
      await deps.backend.unload(slot);
      if (loaded) deps.hub.emit({ type: 'modelUnloaded', id: loaded.id });
    },

    async state() {
      const [storage, memory] = await Promise.all([
        deps.backend.storage(),
        deps.backend.memoryInfo(),
      ]);
      const loaded: Partial<Record<ModelCategory, ModelInfo>> = {};
      for (const [category, slot] of Object.entries(SLOT_OF_CATEGORY) as Array<
        [ModelCategory, LoadSlot]
      >) {
        const entry = LIFECYCLE_CATEGORIES.has(category)
          ? await residentLifecycleModel(category).then((id) => (id ? { id, path: '' } : null))
          : await deps.backend.loaded(slot);
        if (!entry) continue;
        loaded[category] =
          (await infoFor(entry.id)) ??
          ({
            id: entry.id,
            name: entry.id,
            category,
            downloaded: true,
            sizeBytes: 0,
            localPath: entry.path,
          } as ModelInfo);
      }
      return {
        loaded,
        storageUsedBytes: storage.usedBytes,
        storageFreeBytes: storage.freeBytes,
        memoryTotalBytes: memory.totalBytes,
        memoryAvailableBytes: memory.availableBytes,
      };
    },
  };

  // Plan and start one download through commons, and remember it so a restart
  // can pick it up. A model already in flight coalesces onto its running task
  // inside commons rather than starting a second worker.
  async function startDownload(id: string): Promise<{ taskId: string }> {
    deps.requireReady();
    const row = await rowFor(id);
    if (!row) throw SDKException.modelNotFound(id);
    const plan = await downloads.plan(
      DownloadPlanRequest.fromPartial({ modelId: id, model: row })
    );
    if (plan.error) throw SDKException.fromProto(plan.error);
    if (!plan.canStart) {
      throw SDKException.of(
        ErrorCode.STORAGE_ERROR,
        `commons refused to plan a download for ${id}` +
          (plan.warnings.length ? `: ${plan.warnings.join('; ')}` : '')
      );
    }
    const started = await downloads.start(
      DownloadStartRequest.fromPartial({ modelId: id, plan })
    );
    if (started.error) throw SDKException.fromProto(started.error);
    if (!started.accepted) {
      throw SDKException.of(ErrorCode.STORAGE_ERROR, `commons refused to start ${id}`);
    }
    putDownloadTask(
      {
        modelId: id,
        taskId: started.taskId,
        paused: false,
        bytesDownloaded: Number(started.initialProgress?.bytesDownloaded ?? 0),
        totalBytes: Number(plan.totalBytes),
        updatedAtUnixMs: Date.now(),
      },
      baseDir()
    );
    return { taskId: started.taskId };
  }

  // Record where a download landed so the registry — not a filesystem walk — is
  // what later answers `downloaded`. An unregistered id (a bare URL or HF repo
  // loaded without registering) has no row to update, so it reports itself.
  async function markDownloaded(id: string, localPath: string): Promise<ModelInfo> {
    const row = await rowFor(id);
    if (!row) {
      return {
        id,
        name: id,
        category: ModelCategory.LANGUAGE,
        downloaded: true,
        sizeBytes: 0,
        localPath,
      };
    }
    const saved = await abi.update({
      ...row,
      localPath: row.localPath || localPath,
      registryStatus: ModelRegistryStatus.MODEL_REGISTRY_STATUS_DOWNLOADED,
      isAvailable: true,
    });
    return toPublicModelInfo(saved);
  }

  return api;
}

// ---------------------------------------------------------------------------
// lora
// ---------------------------------------------------------------------------

/** LoRA adapters on the loaded language model. */
export interface LoraNamespace {
  /**
   * Apply an adapter to the loaded language model.
   *
   * @throws SDKException when no language model is loaded.
   * @example
   * await RunAnywhere.lora.apply('/models/style-lora.gguf', 0.8);
   */
  apply(adapterId: string, scale?: number): Promise<void>;
  /**
   * Remove one adapter, or all of them when omitted.
   *
   * @deprecated Passing no `adapterId` forwards to {@link removeAll}; call
   *   it directly for new code.
   */
  remove(adapterId?: string): Promise<void>;
  /** Remove every applied adapter. */
  removeAll(): Promise<void>;
  /** Which adapters are applied. */
  list(): Promise<LoraState>;
}

/**
 * Build the `lora` namespace over the lifecycle LoRA ABI.
 *
 * These act on whatever language model `rac_model_lifecycle_load_proto` made
 * resident, which is what makes them work at all: the component handle
 * `rac_llm_component_load_lora` needed stopped existing in F4.
 */
export function createLoraNamespace(deps: AssetDeps): LoraNamespace {
  const lora = new LoraAbi(deps.backend);

  const toPublic = (state: { loadedAdapters: Array<{ adapterId: string; scale?: number }> }) => ({
    applied: state.loadedAdapters.map((a) => ({ id: a.adapterId, scale: a.scale ?? 1 })),
  });

  return {
    async apply(adapterId, scale) {
      deps.requireReady();
      // Commons resolves an adapter id through the LoRA catalog and a path
      // straight from disk, so both forms of the public argument work without
      // the SDK having to tell them apart.
      const result = await lora.apply({
        adapters: [
          isLikelyPath(adapterId)
            ? { adapterId, adapterPath: adapterId, scale }
            : { adapterId, scale },
        ],
        // The public verb has always read as "add this one"; commons' default
        // is SET, which would silently detach everything else.
        keepExisting: true,
      });
      if (result.error) throw SDKException.fromProto(result.error);
    },

    async remove(adapterId) {
      deps.requireReady();
      if (!adapterId) return this.removeAll();
      await lora.remove({ adapterIds: [adapterId], clearAll: false });
    },

    async removeAll() {
      deps.requireReady();
      await lora.remove({ adapterIds: [], clearAll: true });
    },

    async list() {
      deps.requireReady();
      const state = await lora.state();
      if (state.error) throw SDKException.fromProto(state.error);
      return toPublic(state);
    },
  };
}

// An adapter the caller named by path rather than by catalog id. Commons
// accepts either; this only decides which field to put it in.
function isLikelyPath(value: string): boolean {
  return value.includes('/') || value.includes('\\') || /\.(gguf|safetensors|bin)$/i.test(value);
}

// ---------------------------------------------------------------------------
// segmentation
// ---------------------------------------------------------------------------

/** Semantic image segmentation. */
export interface SegmentationNamespace {
  /**
   * Label every pixel of `image`.
   *
   * @throws SDKException when no segmentation model is loaded, or the image is not raw RGB.
   * @example
   * const s = await RunAnywhere.segmentation.segment(image.rawRgb(px, 512, 512));
   * console.log(s.classes.map((c) => c.label));
   */
  segment(input: ImageInput, options?: SegmentationOptions): Promise<SegmentationResult>;
}

/** Build the `segmentation` namespace over a backend. */
export function createSegmentationNamespace(deps: AssetDeps): SegmentationNamespace {
  const data = new DataAbi(deps.backend);
  return {
    async segment(input, options = {}) {
      deps.requireReady();
      if (!input.rgb || !input.width || !input.height) {
        // rac_segmentation_image_t takes decoded pixels only; there is no decoder in
        // commons, so an encoded JPEG/PNG cannot be accepted here.
        throw SDKException.validationFailed({
          fieldPath: 'image',
          message: 'segmentation needs raw RGB pixels — use image.rawRgb(data, width, height)',
        });
      }
      const native = await data.segment(
        toSegmentationRequest(input.rgb, input.width, input.height, {
          includeDiagnosticImage:
            options.includeDiagnosticImage ?? SEGMENTATION_DEFAULTS.includeDiagnosticImage,
        })
      );
      // Commons guarantees the pixel counts sum to width * height before it
      // encodes a result, so the coverage share is an exact division here.
      const pixels = native.width * native.height;
      return {
        classMask: toClassMask(native),
        width: native.width,
        height: native.height,
        classes: native.classSummaries.map((c) => ({
          classId: c.classId,
          label: c.label,
          pixelCount: c.pixelCount,
          fraction: pixels ? c.pixelCount / pixels : 0,
        })),
      };
    },
  };
}

// ---------------------------------------------------------------------------
// images
// ---------------------------------------------------------------------------

/** Diffusion image generation. */
export interface ImagesNamespace {
  /**
   * Generate an image from `prompt`.
   *
   * @throws SDKException — not available on Electron; see the gap note below.
   * @example
   * const r = await RunAnywhere.images.generate('a red bicycle');
   * console.log(r.images[0].width);
   */
  generate(prompt: string, options?: ImageOptions): Promise<ImageResult>;
  /** Stream generation progress and the finished image. */
  generateStream(prompt: string, options?: ImageOptions): AsyncIterableIterator<ImageEvent>;
}

// Commons exposes diffusion only through rac_diffusion_generate_proto (plus the
// Apple platform bridge). The Electron addon links no diffusion backend and the
// diffusion protos are not vendored here, so both verbs report the missing
// symbols rather than pretending to generate.
export const IMAGES_GAP =
  'images.generate on Electron — needs rac_diffusion_generate_proto bound in the addon ' +
  'and a linked diffusion backend (none of llamacpp/onnx/sherpa serves RAC_PRIMITIVE_DIFFUSION)';

/** Build the `images` namespace; every verb reports the unbound diffusion path. */
export function createImagesNamespace(_deps: AssetDeps): ImagesNamespace {
  return {
    generate(): Promise<ImageResult> {
      return Promise.reject(SDKException.notImplemented(IMAGES_GAP));
    },
    generateStream(): AsyncIterableIterator<ImageEvent> {
      return bridgeStream<ImageEvent>((sink) => {
        sink.fail(SDKException.notImplemented(IMAGES_GAP));
      });
    },
  };
}

export { IMAGE_DEFAULTS };
