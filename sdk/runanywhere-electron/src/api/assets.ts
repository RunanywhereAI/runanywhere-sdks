// assets.ts — the `models`, `lora`, `images`, and `segmentation` namespaces.

import { CATALOG, isCatalogId } from '../catalog';
import type { CatalogEntry, ModelType } from '../catalog';
import { SDKException } from '../errors';
import type { LoadSlot, RaBackend } from './backend';
import type { SdkEventHub } from './hub';
import { bridgeStream } from './iter';
import { IMAGE_DEFAULTS, SEGMENTATION_DEFAULTS } from './options';
import type { ImageOptions, LoadOptions, SegmentationOptions } from './options';
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
}

// The catalog's own `type` tags map one-to-one onto public categories and slots.
const CATEGORY_OF_TYPE: Record<ModelType, ModelCategory> = {
  llm: ModelCategory.LANGUAGE,
  vlm: ModelCategory.VISION,
  embedder: ModelCategory.EMBEDDING,
  stt: ModelCategory.SPEECH_TO_TEXT,
  tts: ModelCategory.TEXT_TO_SPEECH,
};

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

const FRAMEWORK_OF_TYPE: Record<ModelType, InferenceFramework> = {
  llm: InferenceFramework.LLAMA_CPP,
  vlm: InferenceFramework.LLAMA_CPP,
  embedder: InferenceFramework.ONNX,
  stt: InferenceFramework.SHERPA,
  tts: InferenceFramework.SHERPA,
};

// Models registered at runtime through models.register(), keyed by id. They live
// alongside the built-in catalog for list/get/download/load.
interface RuntimeModel {
  id: string;
  registration: ModelRegistration;
}

function catalogToInfo(
  id: string,
  entry: CatalogEntry,
  status: { downloaded: boolean; sizeBytes: number }
): ModelInfo {
  return {
    id,
    name: entry.label ?? id,
    category: CATEGORY_OF_TYPE[entry.type],
    framework: FRAMEWORK_OF_TYPE[entry.type],
    downloaded: status.downloaded,
    sizeBytes: status.sizeBytes || (entry.sizeMB ? entry.sizeMB * 1_000_000 : 0),
    parameters: entry.params,
  };
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
  /** Fetch a model, reporting progress and completion in one stream. */
  download(id: string): AsyncIterableIterator<DownloadEvent>;
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
 * Build a `LoadedModel` handle from load context. Cheap placement: the addon
 * does not report actual backend/device per load today, so `actualBackend`
 * falls back to the requested framework, then to the catalog's known engine
 * for built-in ids, and `actualDevice` mirrors `LoadOptions.useGpu`.
 */
function toLoadedModel(
  id: string,
  category: ModelCategory,
  options: LoadOptions,
  unload: (id: string) => Promise<void>
): LoadedModel {
  const actualBackend = options.framework ?? (isCatalogId(id) ? FRAMEWORK_OF_TYPE[CATALOG[id].type] : undefined);
  return {
    id,
    category,
    requestedBackend: options.framework,
    actualBackend,
    actualDevice: options.useGpu ? DevicePlacement.GPU : DevicePlacement.CPU,
    close: () => unload(id),
  };
}

/** Build the `models` namespace over a backend. */
export function createModelsNamespace(deps: AssetDeps): ModelsNamespace {
  const runtime = new Map<string, RuntimeModel>();

  const infoFor = async (id: string): Promise<ModelInfo | null> => {
    const status = await deps.backend.modelStatus();
    if (isCatalogId(id)) {
      return catalogToInfo(id, CATALOG[id], status[id] ?? { downloaded: false, sizeBytes: 0 });
    }
    const custom = runtime.get(id);
    if (!custom) return null;
    const source = sourceFor(custom.registration);
    let downloaded = false;
    let sizeBytes = 0;
    if (custom.registration.path) {
      downloaded = await deps.backend.pathExists(custom.registration.path);
    } else {
      const local = status[id];
      downloaded = local?.downloaded ?? false;
      sizeBytes = local?.sizeBytes ?? 0;
    }
    return {
      id,
      name: custom.registration.name ?? id,
      category: custom.registration.category,
      downloaded,
      sizeBytes,
      localPath: custom.registration.path,
      framework: undefined,
      parameters: undefined,
      ...(source ? {} : {}),
    };
  };

  const slotFor = (category: ModelCategory): LoadSlot => {
    const slot = SLOT_OF_CATEGORY[category];
    if (!slot) {
      throw SDKException.notImplemented(`loading ${category} models on Electron`);
    }
    return slot;
  };

  const categoryOf = async (id: string): Promise<ModelCategory> => {
    if (isCatalogId(id)) return CATEGORY_OF_TYPE[CATALOG[id].type];
    const custom = runtime.get(id);
    if (custom) return custom.registration.category;
    throw SDKException.modelNotFound(id);
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

  const resolveSource = async (id: string): Promise<string> => {
    if (isCatalogId(id)) return id;
    const custom = runtime.get(id);
    if (custom) return sourceFor(custom.registration);
    // An unregistered id may still be a directly loadable source (HF repo, URL, path).
    return id;
  };

  const api: ModelsNamespace = {
    async list(filter = {}) {
      const status = await deps.backend.modelStatus();
      const out: ModelInfo[] = [];
      for (const [id, entry] of Object.entries(CATALOG)) {
        out.push(catalogToInfo(id, entry, status[id] ?? { downloaded: false, sizeBytes: 0 }));
      }
      for (const id of runtime.keys()) {
        const info = await infoFor(id);
        if (info) out.push(info);
      }
      return out.filter(
        (m) =>
          (!filter.category || m.category === filter.category) &&
          (!filter.downloadedOnly || m.downloaded)
      );
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
      const id = model.id ?? sourceFor(model);
      runtime.set(id, { id, registration: { ...model } });
      const info = await infoFor(id);
      if (!info) throw SDKException.modelNotFound(id);
      return info;
    },

    download(id) {
      return bridgeStream<DownloadEvent>(async (sink) => {
        const source = await resolveSource(id);
        let extracting = false;
        const resolved = await deps.backend.resolveModel(source, (p) => {
          sink.push({
            type: 'progress',
            bytesDone: p.received,
            bytesTotal: p.total,
            percent: p.percent,
          });
          // An archive entry reports 100% while the tar extract still runs; surface
          // that as its own phase rather than a stall at 100.
          if (!extracting && p.percent >= 100 && isCatalogId(source) && CATALOG[source].archive) {
            extracting = true;
            sink.push({ type: 'extracting' });
          }
        });
        const info = (await infoFor(id)) ?? {
          id,
          name: id,
          category: await categoryOf(id).catch(() => ModelCategory.LANGUAGE),
          downloaded: true,
          sizeBytes: 0,
          localPath: resolved.primary,
        };
        sink.push({ type: 'completed', model: { ...info, downloaded: true, localPath: resolved.primary } });
      });
    },

    async delete(id) {
      const category = await categoryOf(id).catch(() => null);
      if (category) {
        const slot = SLOT_OF_CATEGORY[category];
        const loaded = slot ? await deps.backend.loaded(slot) : null;
        // Deleting the files under a live handle would leave the engine reading a
        // path that no longer exists, so release it first.
        if (slot && loaded && loaded.id === id) await deps.backend.unload(slot);
      }
      await deps.backend.deleteModel(id);
      runtime.delete(id);
      deps.hub.emit({ type: 'modelUnloaded', id });
    },

    async load(id, options = {}) {
      deps.requireReady();
      const category = await categoryOf(id);
      const slot = slotFor(category);
      const loaded = await deps.backend.ensure(slot, await resolveSource(id), {
        framework: options.framework,
        contextLength: options.contextLength,
        threads: options.threads,
        useGpu: options.useGpu,
      });
      const model = toLoadedModel(loaded.id, category, options, api.unload);
      deps.hub.emit({ type: 'modelLoaded', id: loaded.id, category, actualBackend: model.actualBackend });
      return model;
    },

    async unload(id) {
      deps.requireReady();
      const category = await categoryOf(id).catch(() => null);
      if (!category) return;
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
        await deps.backend.unload();
        for (const p of previous) if (p) deps.hub.emit({ type: 'modelUnloaded', id: p.id });
        return;
      }
      const slot = slotFor(category);
      const loaded = await deps.backend.loaded(slot);
      await deps.backend.unload(slot);
      if (loaded) deps.hub.emit({ type: 'modelUnloaded', id: loaded.id });
    },

    async state() {
      const storage = await deps.backend.storage();
      const loaded: Partial<Record<ModelCategory, ModelInfo>> = {};
      for (const [category, slot] of Object.entries(SLOT_OF_CATEGORY) as Array<
        [ModelCategory, LoadSlot]
      >) {
        const entry = await deps.backend.loaded(slot);
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
      };
    },
  };
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

/** Build the `lora` namespace over a backend. */
export function createLoraNamespace(deps: AssetDeps): LoraNamespace {
  const pathFor = async (adapterId: string): Promise<string> => {
    // An adapter registers like any other artifact, so an id resolves through the
    // same download path; a plain filesystem path passes straight through.
    const resolved = await deps.backend.resolveModel(adapterId);
    return resolved.primary;
  };

  return {
    async apply(adapterId, scale) {
      deps.requireReady();
      await deps.backend.loraApply(await pathFor(adapterId), scale ?? 1.0);
    },
    async remove(adapterId) {
      deps.requireReady();
      await deps.backend.loraRemove(adapterId ? await pathFor(adapterId) : undefined);
    },
    async removeAll() {
      deps.requireReady();
      await deps.backend.loraRemove(undefined);
    },
    async list() {
      const applied = await deps.backend.loraList();
      return { applied: applied.map((a) => ({ id: a.id, scale: a.scale })) };
    },
  };
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
  return {
    async segment(input, options = {}) {
      deps.requireReady();
      const loaded = await deps.backend.loaded('segmentation');
      if (!loaded) {
        throw SDKException.invalidState(
          'no segmentation model is loaded — call models.load() first'
        );
      }
      if (!input.rgb || !input.width || !input.height) {
        // rac_segmentation_image_t takes decoded pixels only; there is no decoder in
        // commons, so an encoded JPEG/PNG cannot be accepted here.
        throw SDKException.validationFailed({
          fieldPath: 'image',
          message: 'segmentation needs raw RGB pixels — use image.rawRgb(data, width, height)',
        });
      }
      const native = await deps.backend.segment(
        { data: input.rgb, width: input.width, height: input.height, pixelFormat: 1 },
        {
          includeDiagnosticImage:
            options.includeDiagnosticImage ?? SEGMENTATION_DEFAULTS.includeDiagnosticImage,
        }
      );
      return {
        classMask: native.classMask,
        width: native.width,
        height: native.height,
        classes: native.classes.map((c) => ({
          classId: c.classId,
          label: c.label,
          pixelCount: c.pixelCount,
          fraction: c.fraction,
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
