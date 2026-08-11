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
} from '@runanywhere/proto-ts/download_service';
import { DownloadAbi, isTerminalState, toProgressSnapshot } from './download-abi';
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
  ModelImportRequest,
  ModelRegistryStatus,
  ModelSource,
  ModelInfo as ProtoModelInfo,
} from '@runanywhere/proto-ts/model_types';
import type { ModelImportResult, ModelLoadResult } from '@runanywhere/proto-ts/model_types';
import {
  LoraAdapterCatalogEntry,
  LoraAdapterCatalogQuery,
  LoraAdapterConfig,
} from '@runanywhere/proto-ts/lora_options';
import type {
  LoraAdapterCatalogListResult,
  LoraCompatibilityResult,
  LoraState as ProtoLoraState,
} from '@runanywhere/proto-ts/lora_options';
import type { SDKError } from '@runanywhere/proto-ts/errors';
import {
  DevicePlacement,
  InferenceFramework,
  ModelCategory,
  requireOneOf,
  toProtoError,
} from './types';
import type {
  DiscoveredModel,
  DownloadEvent,
  DownloadProgressSnapshot,
  ImageEvent,
  ImageInput,
  ImageResult,
  LoadedModel,
  LoraState,
  ModelCompatibility,
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
  // VOICE_ACTIVITY has no addon slot at all — `rac_vad_*_proto` is handle-free
  // like stt/tts, and commons maps the category onto SDK_COMPONENT_VAD in its
  // lifecycle store (`model_lifecycle_translation.cpp`). It is here so a voice
  // session can make the catalogued Silero VAD resident instead of refusing to
  // open; before this, `models.load` of a VAD threw "not implemented".
  ModelCategory.VOICE_ACTIVITY,
  // RERANK is deliberately absent: rac_rerank_component_rerank_proto is the
  // only rerank entry point commons exposes and it takes a component handle,
  // so the reranker stays in an addon slot.
]);

/**
 * Every category the SDK can hold resident, whichever store it lives in.
 *
 * `SLOT_OF_CATEGORY` used to stand in for this, which silently excluded any
 * lifecycle-only category from residency accounting and from `state().loaded`.
 */
const MANAGED_CATEGORIES: readonly ModelCategory[] = [
  ...LIFECYCLE_CATEGORIES,
  ...(Object.keys(SLOT_OF_CATEGORY) as ModelCategory[]).filter(
    (category) => !LIFECYCLE_CATEGORIES.has(category)
  ),
];

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

/** What {@link ModelsNamespace.discover} should sweep. */
export interface DiscoverOptions {
  /** Extra roots to walk on top of the model store. */
  searchRoots?: string[];
  /** Walk each root's subdirectories. Off by default. */
  recursive?: boolean;
  /** Point a matching registry row at what was found. On by default. */
  linkDownloaded?: boolean;
  /** Include the built-in catalog rows in the sweep. Off by default. */
  includeBuiltIn?: boolean;
  /** Include models a previous `import` adopted. On by default. */
  includeUserImports?: boolean;
  /** Clear rows whose artifacts turned out to be gone. Off by default. */
  purgeInvalid?: boolean;
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
  /**
   * Whether an interrupted download left bytes on disk that the next
   * {@link download} continues from instead of refetching.
   *
   * Starting a download *is* resuming it, so this says nothing about how to
   * resume — only whether resuming would save work. It exists so a UI can label
   * the button honestly: offering "Resume" when the bytes are gone is a lie, and
   * offering "Download" when 90% of a 3 GB file is already here understates it.
   *
   * Answered from bytes on disk rather than from session state, so it stays
   * right across a relaunch — which is the case that matters, because an
   * interrupted multi-gigabyte transfer is usually discovered on the next
   * launch and not in the run that started it.
   */
  isResumable(id: string): Promise<boolean>;
  /**
   * Remove a model's files from the store, keeping its registry row so it goes
   * back to "not downloaded" rather than disappearing from {@link list}.
   * Dropping the row is {@link unregister}'s job.
   */
  delete(id: string): Promise<void>;
  /**
   * Adopt a model already on disk: normalize its path, optionally copy it into
   * the managed store, validate it, and write the registry row — all in commons.
   *
   * This is the local-file entry point a file picker feeds. `register({path})`
   * only writes a row and validates nothing.
   */
  import(request: ModelImportRequest): Promise<ModelImportResult>;
  /**
   * Sweep the model store for artifacts and report what is there, linking each
   * one to its registry row. {@link refresh} is the same sweep expressed as
   * "reconcile the registry"; this one hands back what was found.
   */
  discover(options?: DiscoverOptions): Promise<DiscoveredModel[]>;
  /**
   * Whether this machine can run and store `id`, straight from commons.
   *
   * The same check {@link load} runs before it admits a model, exposed so a
   * Models list can badge a row before the user commits to a multi-gigabyte
   * download.
   *
   * @throws SDKException when `id` has no registry row — an unknown model has no
   *   declared requirement, and answering "compatible" for one would be a guess.
   */
  compatibility(id: string): Promise<ModelCompatibility>;
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

  /** What occupies `category` right now, from whichever store owns it. */
  const residentModelId = async (category: ModelCategory): Promise<string | null> => {
    if (LIFECYCLE_CATEGORIES.has(category)) return residentLifecycleModel(category);
    const slot = SLOT_OF_CATEGORY[category];
    return slot ? (await deps.backend.loaded(slot))?.id ?? null : null;
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
        MANAGED_CATEGORIES.map(async (category) => {
          const id = await residentModelId(category);
          return id ? { category, id } : null;
        })
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
        // Every arm carries the same operationId and a monotonically increasing
        // sequence, so a consumer that received events out of band (over an RPC
        // port, say) can order and correlate them without keeping its own
        // counter. The model id stands in until commons reports the task id it
        // actually assigned.
        let operationId = id;
        let sequence = 0;
        const next = (): number => {
          sequence += 1;
          return sequence;
        };
        // Already here: commons plans a fresh transfer into its own model folder
        // and has no "this is already downloaded" short circuit, so asking it
        // would refetch a model the caller can already load.
        const present = await rowFor(id);
        if (present?.localPath && (await deps.backend.pathExists(present.localPath))) {
          sink.push({ type: 'started', operationId, sequence: next() });
          sink.push({
            type: 'completed',
            operationId,
            sequence: next(),
            model: toPublicModelInfo(present),
          });
          return;
        }
        const started = await startDownload(id);
        operationId = started.taskId || operationId;
        let announced = false;
        let verifying = false;
        let last: DownloadProgress | null = null;
        const poll = (): Promise<DownloadProgress> =>
          downloads.poll(
            DownloadSubscribeRequest.fromPartial({ modelId: id, taskId: started.taskId })
          );
        await watcher.follow(id, (progress) => {
          last = progress;
          if (progress.taskId) operationId = progress.taskId;
          if (!announced) {
            announced = true;
            sink.push({ type: 'started', operationId, sequence: next() });
          }
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
          switch (progress.state) {
            case DownloadState.DOWNLOAD_STATE_VALIDATING:
              // Checksum / expected-files verification. Announced once: it is a
              // phase rather than a measurement, and commons reports no progress
              // within it.
              if (!verifying) {
                verifying = true;
                sink.push({ type: 'verifying', operationId, sequence: next() });
              }
              return;
            case DownloadState.DOWNLOAD_STATE_EXTRACTING:
              // Extraction does report its own stage progress, so unlike
              // verification every tick is forwarded — a multi-gigabyte archive
              // takes long enough that a frozen bar reads as a hang.
              sink.push({
                type: 'extracting',
                operationId,
                sequence: next(),
                percent: progress.stageProgress > 0 ? progress.stageProgress * 100 : undefined,
              });
              return;
            // The three terminal states are named so they cannot fall into the
            // progress arm: each is re-reported below as the stream's own
            // terminal event, and a progress snapshot alongside would announce a
            // live byte count for a transfer that has already stopped.
            case DownloadState.DOWNLOAD_STATE_COMPLETED:
            case DownloadState.DOWNLOAD_STATE_FAILED:
            case DownloadState.DOWNLOAD_STATE_CANCELLED:
              return;
            default:
              // Everything else — pending, downloading, retrying, paused,
              // resuming — is a transfer still in motion and reads as progress.
              sink.push({
                type: 'progress',
                snapshot: toProgressSnapshot(progress, operationId, next()),
              });
              return;
          }
        }, poll);
        const terminal = last as DownloadProgress | null;
        await downloads.cleanup();
        if (!announced) sink.push({ type: 'started', operationId, sequence: next() });
        if (terminal?.state === DownloadState.DOWNLOAD_STATE_FAILED) {
          dropDownloadTask(id, baseDir());
          notify('Download failed', `${id}: ${terminal.error?.message ?? 'unknown error'}`);
          // A terminal event rather than a throw: a consumer that has been
          // rendering a progress bar needs to know the transfer failed without a
          // `try` wrapped around its render loop, and the retry affordance it
          // shows is driven by which arm arrived.
          sink.push({
            type: 'failed',
            operationId,
            sequence: next(),
            error: toProtoError(
              terminal.error
                ? SDKException.fromProto(terminal.error)
                : SDKException.of(ErrorCode.ERROR_CODE_STORAGE_ERROR, `download failed for ${id}`)
            ),
          });
          return;
        }
        if (terminal?.state === DownloadState.DOWNLOAD_STATE_CANCELLED) {
          // pause() and cancel() own the persisted bookkeeping; the stream owes
          // the caller only the terminal arm that says which way it ended.
          sink.push({ type: 'cancelled', operationId, sequence: next() });
          return;
        }
        if (terminal?.state !== DownloadState.DOWNLOAD_STATE_COMPLETED) {
          // The watcher only returns on a terminal state, so reaching here means
          // the transfer stopped without commons reporting one. The grammar has
          // no silent finish, and claiming `completed` for bytes nothing verified
          // is exactly the lie the terminal arms exist to prevent.
          sink.push({
            type: 'failed',
            operationId,
            sequence: next(),
            error: toProtoError(
              SDKException.of(
                ErrorCode.ERROR_CODE_STORAGE_ERROR,
                `the download of ${id} ended without a terminal state from commons`
              )
            ),
          });
          return;
        }
        dropDownloadTask(id, baseDir());
        const info = await markDownloaded(id, terminal.localPath ?? '');
        notify('Download complete', info.name || id);
        sink.push({ type: 'completed', operationId, sequence: next(), model: info });
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

    async isResumable(id) {
      deps.requireReady();
      const row = await rowFor(id);
      if (!row) return false;
      // Already here: there is nothing to continue. Offering "Resume" for a
      // complete model is the same lie in the other direction.
      if (row.localPath && (await deps.backend.pathExists(row.localPath))) return false;
      // Commons owns the storage layout, so it is the only thing that can say
      // where this model's ".part" sidecars live; planning measures them and
      // reports `canResume`/`resumeFromBytes` whatever else it concludes about
      // the transfer. That is the disk-truth answer, and it survives a relaunch.
      const plan = await downloads
        .plan(DownloadPlanRequest.fromPartial({ modelId: id, model: row }))
        .catch(() => null);
      if (plan) return plan.canResume && Number(plan.resumeFromBytes) > 0;
      // Planning HEADs each file for a definitive size, so it needs the network
      // — and an offline launch is exactly when a UI has to label the button.
      // Fall back to what the last run recorded about this transfer.
      const task = readDownloadTasks(baseDir()).find((t) => t.modelId === id);
      return !!task && task.bytesDownloaded > 0;
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
          ErrorCode.ERROR_CODE_STORAGE_ERROR,
          `commons deleted the model store folder for ${id} but ${row.localPath} is still on ` +
            'disk: this row points outside the commons model store, so its files have to be ' +
            'removed by whatever put them there'
        );
      }
      // The registry ROW stays. Commons' delete already cleared its local path,
      // and clearing that is what flips `registry_status` back to REGISTERED —
      // so the model reads as available-to-download instead of vanishing from
      // `list()` until the next process start reseeds the catalog. Removing the
      // row is `unregister`'s job, and doing both here was `delete` quietly
      // being `delete` + `unregister`.
      dropDownloadTask(id, baseDir());
      deps.hub.emit({ type: 'modelUnloaded', id });
    },

    async import(request) {
      deps.requireReady();
      // Normalized before encoding: the nested `ModelInfo` is a full proto
      // message, and encoding one whose scalars are absent throws out of the
      // writer rather than defaulting them the way proto3 means.
      const result = await abi.import(ModelImportRequest.fromPartial(request));
      if (result.error) throw SDKException.fromProto(result.error);
      return result;
    },

    async discover(options = {}) {
      deps.requireReady();
      const result = await abi.discover({
        searchRoots: options.searchRoots ?? [],
        recursive: options.recursive ?? false,
        linkDownloaded: options.linkDownloaded ?? true,
        includeBuiltIn: options.includeBuiltIn ?? false,
        includeUserImports: options.includeUserImports ?? true,
        purgeInvalid: options.purgeInvalid ?? false,
      });
      if (result.error) throw SDKException.fromProto(result.error);
      return result.discoveredModels.map((found) => ({
        id: found.modelId,
        localPath: found.localPath,
        matchedRegistry: found.matchedRegistry,
        sizeBytes: Number(found.sizeBytes),
        model: found.model ? toPublicModelInfo(found.model) : undefined,
        warnings: found.warnings,
      }));
    },

    compatibility(id) {
      deps.requireReady();
      return residency.check(id);
    },

    async load(id, options = {}) {
      deps.requireReady();
      const row = await rowFor(id);
      const category = row ? categoryFromProto(row.category) : undefined;
      if (!category) throw SDKException.modelNotFound(id);
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
        // `validateAvailability` is what makes this one call satisfy the whole
        // documented contract: commons checks its own storage layout, and when
        // the artifact is not there it runs plan → start → poll on the download
        // orchestrator and re-reads the row before resolving the path. Fetching
        // here instead would be a second downloader writing to a second layout,
        // which is exactly what left `load()` pointed at a file that was never
        // going to exist. A VLM's projector rides along in the row's
        // VISION_PROJECTOR descriptor, which is what commons' resolver matches.
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

      const loaded = await deps.backend.ensure(slotFor(category), await resolveSource(id), {
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
      for (const category of MANAGED_CATEGORIES) {
        const residentId = await residentModelId(category);
        if (!residentId) continue;
        loaded[category] =
          (await infoFor(residentId)) ??
          ({
            id: residentId,
            name: residentId,
            category,
            downloaded: true,
            sizeBytes: 0,
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
        ErrorCode.ERROR_CODE_STORAGE_ERROR,
        `commons refused to plan a download for ${id}` +
          (plan.warnings.length ? `: ${plan.warnings.join('; ')}` : '')
      );
    }
    const started = await downloads.start(
      DownloadStartRequest.fromPartial({ modelId: id, plan })
    );
    if (started.error) throw SDKException.fromProto(started.error);
    if (!started.accepted) {
      throw SDKException.of(ErrorCode.ERROR_CODE_STORAGE_ERROR, `commons refused to start ${id}`);
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

/**
 * The tag that marks a registry row as adapter bytes rather than a loadable
 * base model, and the id prefix those rows carry. Both match Swift's
 * `LoRAArtifactMetadata` exactly, so an adapter downloaded by one SDK is
 * recognizable to the others reading the same store.
 */
const LORA_ADAPTER_TAG = 'lora-adapter';
const LORA_ARTIFACT_ID_PREFIX = 'lora-adapter:';

/** The registry id an adapter's downloadable bytes are filed under. */
function loraArtifactModelId(adapterId: string): string {
  return adapterId.startsWith(LORA_ARTIFACT_ID_PREFIX)
    ? adapterId
    : LORA_ARTIFACT_ID_PREFIX + adapterId;
}

/** LoRA adapters: the catalog of them, and the ones applied to the loaded LLM. */
export interface LoraNamespace {
  /**
   * Apply an adapter to the loaded language model.
   *
   * A catalog id is resolved through {@link getCatalogEntry} to the file on
   * disk, because commons has no id→path resolver on the apply path — its
   * `LoraAdapterConfig.adapter_path` is documented as "commons still loads
   * strictly from this path". A value that looks like a path is used as one, so
   * a loose adapter that was never catalogued still works.
   *
   * @throws SDKException when no language model is loaded, when `adapterId` is
   *   not a registered adapter, or when that adapter has no local file yet.
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
  /** Which adapters are applied to the loaded model. */
  list(): Promise<LoraState>;
  /**
   * The LoRA service's own snapshot: every adapter loaded into the base model's
   * context, applied or not, with the rank/alpha/size each one reports.
   * {@link list} is the same read narrowed to what is actually applied.
   */
  state(): Promise<ProtoLoraState>;
  /**
   * Whether an adapter can be applied to the loaded base model.
   *
   * Never throws for "nothing is loaded": commons answers with
   * `isCompatible: false` and the reason inside the result, so a UI can badge a
   * row without a `try`.
   */
  checkCompatibility(config: LoraAdapterConfig): Promise<LoraCompatibilityResult>;

  // ---- catalog ----

  /** Add or replace one catalog entry, and read back the canonical row. */
  register(entry: LoraAdapterCatalogEntry): Promise<LoraAdapterCatalogEntry>;
  /**
   * Register the entry AND the model-registry row describing where its bytes
   * come from, so {@link download} can fetch them on the ordinary model
   * download path — with resume, checksums, and progress — instead of an
   * app-side transfer into an app-invented layout.
   *
   * `artifact.id` defaults to the adapter's `lora-adapter:<id>` registry id.
   */
  registerArtifact(
    entry: LoraAdapterCatalogEntry,
    artifact: ProtoModelInfo
  ): Promise<ProtoModelInfo>;
  /**
   * Register and fetch an adapter in one call, resolving to its path on disk.
   *
   * The catalog entry's `localPath` is filled in on success, which is what
   * makes {@link apply} work by id afterwards — a non-empty `local_path` is the
   * proto's single definition of "downloaded".
   */
  download(
    entry: LoraAdapterCatalogEntry,
    artifact: ProtoModelInfo,
    onProgress?: (snapshot: DownloadProgressSnapshot) => void
  ): Promise<string>;
  /**
   * Adopt an adapter file the user picked, copying it into managed storage and
   * registering it as adapter bytes. Does NOT associate it with a catalog
   * entry — call {@link register} with the matching entry once the caller knows
   * which adapter the file is.
   */
  importAdapter(sourcePath: string): Promise<ModelImportResult>;
  /** Every catalog entry, with unfiltered and downloaded counts. */
  listCatalog(query?: LoraAdapterCatalogQuery): Promise<LoraAdapterCatalogListResult>;
  /** Catalog entries matching `query` (by model, tags, text, or downloaded-ness). */
  queryCatalog(query: LoraAdapterCatalogQuery): Promise<LoraAdapterCatalogListResult>;
  /** One catalog entry, or null when `adapterId` is not registered. */
  getCatalogEntry(adapterId: string): Promise<LoraAdapterCatalogEntry | null>;
  /** The adapters declared compatible with `modelId`. */
  adaptersForModel(modelId: string): Promise<LoraAdapterCatalogEntry[]>;
  /** Every registered adapter. */
  allRegistered(): Promise<LoraAdapterCatalogEntry[]>;
}

/** What the lora namespace needs beyond {@link AssetDeps}. */
export interface LoraDeps extends AssetDeps {
  /**
   * The facade's own `models`, not a second one: {@link LoraNamespace.download}
   * runs on the model download path, and a namespace built here would open a
   * second process-wide progress subscription that displaces the first.
   */
  models: ModelsNamespace;
}

/**
 * Build the `lora` namespace over the LoRA ABI.
 *
 * The runtime verbs act on whatever language model
 * `rac_model_lifecycle_load_proto` made resident, which is what makes them work
 * at all: the component handle `rac_llm_component_load_lora` needed stopped
 * existing in F4. The catalog verbs act on the process-wide LoRA registry,
 * which outlives any loaded model.
 */
export function createLoraNamespace(deps: LoraDeps): LoraNamespace {
  const lora = new LoraAbi(deps.backend);
  const abi = new ModelAbi(deps.backend);

  // Swift filters on `applied`; mapping every loaded adapter over-reports the
  // ones commons loaded but did not attach.
  const toPublic = (state: ProtoLoraState): LoraState => ({
    applied: state.loadedAdapters
      .filter((a) => a.applied)
      .map((a) => ({ id: a.adapterId, scale: a.scale ?? 1 })),
  });

  const orThrow = <T extends { error?: SDKError | undefined }>(result: T): T => {
    if (result.error) throw SDKException.fromProto(result.error);
    return result;
  };

  const getEntry = async (adapterId: string): Promise<LoraAdapterCatalogEntry | null> => {
    const result = await lora.getCatalogEntry({ adapterId });
    // An unknown id comes back `found: false` carrying a "not found" envelope,
    // which is an answer and not a failure — the same shape `ModelAbi.get`
    // reads. Anything that actually went wrong arrives as a rejected promise
    // from the addon's proto-buffer status.
    if (!result.found) return null;
    return orThrow(result).entry ?? null;
  };

  /** The adapter config `apply` sends, with the path commons insists on. */
  const resolveAdapter = async (
    adapterId: string,
    scale: number | undefined
  ): Promise<LoraAdapterConfig> => {
    if (isLikelyPath(adapterId)) {
      return LoraAdapterConfig.fromPartial({ adapterId, adapterPath: adapterId, scale });
    }
    const entry = await getEntry(adapterId);
    if (!entry) throw SDKException.modelNotFound(`LoRA adapter '${adapterId}'`);
    if (!entry.localPath) {
      throw SDKException.invalidState(
        `LoRA adapter '${adapterId}' is registered but has no local file — call lora.download() ` +
          'or lora.importAdapter() first'
      );
    }
    return LoraAdapterConfig.fromPartial({
      adapterId: entry.id,
      adapterPath: entry.localPath,
      // The publisher's recommended strength is the catalog's job to remember.
      scale: scale ?? entry.defaultScale,
    });
  };

  const api: LoraNamespace = {
    async apply(adapterId, scale) {
      deps.requireReady();
      const result = await lora.apply({
        adapters: [await resolveAdapter(adapterId, scale)],
        // The public verb has always read as "add this one"; commons' default
        // is SET, which would silently detach everything else.
        keepExisting: true,
      });
      orThrow(result);
    },

    async remove(adapterId) {
      deps.requireReady();
      if (!adapterId) return api.removeAll();
      await lora.remove({ adapterIds: [adapterId], clearAll: false });
    },

    async removeAll() {
      deps.requireReady();
      await lora.remove({ adapterIds: [], clearAll: true });
    },

    async list() {
      deps.requireReady();
      return toPublic(orThrow(await lora.list()));
    },

    async state() {
      deps.requireReady();
      return orThrow(await lora.state());
    },

    checkCompatibility(config) {
      deps.requireReady();
      return lora.checkCompatibility(config);
    },

    async register(entry) {
      deps.requireReady();
      return lora.register(entry);
    },

    async registerArtifact(entry, artifact) {
      deps.requireReady();
      await lora.register(entry);
      const tags = artifact.metadata?.tags ?? [];
      const tagged = ProtoModelInfo.fromPartial({
        ...artifact,
        id: artifact.id || loraArtifactModelId(entry.id),
        name: artifact.name || entry.name || entry.id,
        metadata: {
          ...artifact.metadata,
          tags: tags.includes(LORA_ADAPTER_TAG) ? tags : [...tags, LORA_ADAPTER_TAG],
        },
      });
      return abi.register(tagged);
    },

    async download(entry, artifact, onProgress) {
      deps.requireReady();
      const registered = await api.registerArtifact(entry, artifact);
      let localPath = '';
      for await (const event of deps.models.download(registered.id)) {
        if (event.type === 'progress') onProgress?.(event.snapshot);
        else if (event.type === 'completed') localPath = event.model.localPath ?? '';
        else if (event.type === 'failed') throw SDKException.fromProto(event.error);
        else if (event.type === 'cancelled') {
          throw SDKException.invalidState(`the download of LoRA adapter '${entry.id}' was cancelled`);
        }
      }
      if (!localPath) {
        // The transfer completed but the terminal event carried no path — the
        // registry row is the record of where it landed.
        localPath = (await abi.get(registered.id))?.localPath ?? '';
      }
      if (!localPath) {
        throw SDKException.of(
          ErrorCode.ERROR_CODE_DOWNLOAD_FAILED,
          `LoRA adapter '${entry.id}' downloaded but no local path was recorded`
        );
      }
      // Commons has no verb left that writes this back (the LoRA-domain
      // download bookkeeping messages were deleted from the IDL), and a
      // non-empty local_path is the proto's only "downloaded" signal — so the
      // catalog is completed here, or `apply(entry.id)` could never resolve.
      await lora.register(LoraAdapterCatalogEntry.fromPartial({ ...entry, localPath }));
      return localPath;
    },

    importAdapter(sourcePath) {
      deps.requireReady();
      return deps.models.import(
        ModelImportRequest.fromPartial({
          model: { metadata: { tags: [LORA_ADAPTER_TAG] } },
          sourcePath,
          copyIntoManagedStorage: true,
          validateBeforeRegister: true,
        })
      );
    },

    async listCatalog(query) {
      deps.requireReady();
      return orThrow(await lora.listCatalog({ query }));
    },

    async queryCatalog(query) {
      deps.requireReady();
      return orThrow(await lora.queryCatalog(query));
    },

    async getCatalogEntry(adapterId) {
      deps.requireReady();
      return getEntry(adapterId);
    },

    async adaptersForModel(modelId) {
      return (await api.queryCatalog(LoraAdapterCatalogQuery.fromPartial({ modelId }))).entries;
    },

    async allRegistered() {
      return (await api.listCatalog()).entries;
    },
  };

  return api;
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
