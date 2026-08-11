// catalog.ts — the app's model table, staged for the commons registry.
//
// The SDK owns the entry SHAPE; the APP owns WHICH models it offers. That split
// matches every other platform in this repo (iOS `ModelCatalogBootstrap.swift`,
// Android `ModelCatalog.kt`, web `model-catalog.ts` — all in `examples/`, none in
// an SDK), and it is what lets two apps ship different model lists against one
// SDK build.
//
// What this file is NOT is the model database. `RunAnywhere.initialize()` seeds
// every staged entry into the commons model registry (`catalogModelInfo` below),
// and from then on `models.list`/`get`/`load` read commons, not this map.
// Registration is buffered here because an app registers before the native addon
// exists — the app preload and the SDK utility `host` both register at module load.
//
// Callers can also pass a HuggingFace repo id, a direct URL, or a local path, so
// an app that registers nothing still resolves those.

import {
  ArchiveType,
  InferenceFramework,
  ModelCategory,
  ModelFileRole,
  ModelFormat,
  ModelInfo,
  ModelRegistryStatus,
  ModelSource,
} from '@runanywhere/proto-ts/model_types';

export type ModelType =
  | 'llm'
  | 'vlm'
  | 'embedder'
  | 'stt'
  | 'tts'
  | 'diarization'
  | 'segmentation';

export interface CatalogFile {
  url: string;
  /** Filename to save as inside the model's dir. */
  as: string;
}

export interface CatalogEntry {
  type: ModelType;
  files: CatalogFile[];
  /** If true, each downloaded file is a .tar.bz2 to extract in place. */
  archive?: boolean;
  /** Path (relative to the model dir) passed to loadLLM/loadSTT/etc. */
  primary: string;
  /** For VLM: the mmproj path (relative to the model dir). */
  mmproj?: string;
  /** Human-readable name for UIs. */
  label?: string;
  /** Parameter count, e.g. "1.5B". */
  params?: string;
  /** Approximate download size in MB. */
  sizeMB?: number;
  /** Slow / memory-heavy on a CPU-only build. */
  heavy?: boolean;
  /**
   * The weights' licence. NOT all of these are open source — Gemma and Llama
   * carry use restrictions the user accepts by downloading, so a UI that offers
   * the model must be able to say which licence applies and link to it.
   */
  license?: string;
  licenseUrl?: string;
  /**
   * The turn markup this model was trained on. Getting it wrong makes a model
   * ignore the conversation and answer as if every turn were the first.
   */
  chatTemplate?: 'chatml' | 'llama3' | 'gemma' | 'mistral';
  /**
   * Pin the engine for this row instead of inferring one from `type`.
   *
   * The inference in {@link FRAMEWORK_OF_TYPE} is a per-MODALITY default —
   * an `llm` means llama.cpp — which cannot express a model whose weights only
   * one engine can read. A QHexRT bundle is a prebuilt QNN context binary: no
   * other backend can load it, and llama.cpp would be handed a `.bin` it has no
   * way to parse. Naming the engine on the ROW is also what keeps
   * `actualBackend` meaningful after load — commons reports what it routed to,
   * so a row that pinned QHEXRT and came back LLAMA_CPP is a visible fallback
   * rather than a silent one.
   */
  framework?: 'llamacpp' | 'onnx' | 'sherpa' | 'qhexrt';
}

/** A model table: catalog id -> entry. */
export type Catalog = Record<string, CatalogEntry>;

// Null-prototype so an id can never collide with an Object.prototype member
// (`toString`, `constructor`, `__proto__`); `isCatalogId` still goes through
// Object.prototype.hasOwnProperty rather than trusting the map's own shape.
const registry: Catalog = Object.create(null) as Catalog;

/**
 * Add an app's models to this process's registry. Merges, so it can be called
 * more than once (last write wins per id) — e.g. a base table plus an opt-in
 * extension. Registration is per-process: register in EVERY process that
 * resolves or lists models.
 */
export function registerCatalog(entries: Catalog): void {
  for (const [id, entry] of Object.entries(entries)) registry[id] = entry;
}

/** Drop every registered model. For tests and for replacing a table wholesale. */
export function clearCatalog(): void {
  for (const id of Object.keys(registry)) delete registry[id];
}

/** Every registered model, as a plain id -> entry map. */
export function catalogEntries(): Readonly<Catalog> {
  return registry;
}

/** One entry, or undefined when `id` is not a registered catalog id. */
export function catalogEntry(id: string): CatalogEntry | undefined {
  return isCatalogId(id) ? registry[id] : undefined;
}

export function isCatalogId(idOrPath: string): boolean {
  return Object.prototype.hasOwnProperty.call(registry, idOrPath);
}

const CATEGORY_OF_TYPE: Record<ModelType, ModelCategory> = {
  llm: ModelCategory.MODEL_CATEGORY_LANGUAGE,
  vlm: ModelCategory.MODEL_CATEGORY_VISION,
  embedder: ModelCategory.MODEL_CATEGORY_EMBEDDING,
  stt: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
  tts: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
  diarization: ModelCategory.MODEL_CATEGORY_SPEAKER_DIARIZATION,
  segmentation: ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION,
};

const FRAMEWORK_OF_TYPE: Record<ModelType, InferenceFramework> = {
  llm: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
  vlm: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
  embedder: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
  stt: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
  tts: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
  diarization: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
  segmentation: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
};

/** Engine names a catalog row may pin, as the proto enum commons stores. */
const FRAMEWORK_BY_NAME: Record<
  NonNullable<CatalogEntry['framework']>,
  InferenceFramework
> = {
  llamacpp: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
  onnx: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
  sherpa: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
  qhexrt: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
};

function frameworkOf(entry: CatalogEntry): InferenceFramework {
  return entry.framework !== undefined
    ? FRAMEWORK_BY_NAME[entry.framework]
    : FRAMEWORK_OF_TYPE[entry.type];
}

function formatOf(entry: CatalogEntry): ModelFormat {
  // A QHexRT row is a prebuilt QNN context bundle, and the format follows from
  // the ENGINE rather than the primary file's extension: the primary is the
  // bundle manifest (`*.json`), which the extension ladder below would read as a
  // plain folder. Commons rejects that pairing at registration — the row simply
  // never appears in models.list(), so the model is invisible in a picker with
  // no error anywhere to explain it.
  if (entry.framework === 'qhexrt') return ModelFormat.MODEL_FORMAT_QNN_CONTEXT;
  if (entry.archive) return ModelFormat.MODEL_FORMAT_FOLDER;
  if (/\.gguf$/i.test(entry.primary)) return ModelFormat.MODEL_FORMAT_GGUF;
  if (/\.onnx$/i.test(entry.primary)) return ModelFormat.MODEL_FORMAT_ONNX;
  if (/\.ort$/i.test(entry.primary)) return ModelFormat.MODEL_FORMAT_ORT;
  if (/\.bin$/i.test(entry.primary)) return ModelFormat.MODEL_FORMAT_BIN;
  return ModelFormat.MODEL_FORMAT_FOLDER;
}

/**
 * A staged entry as the `runanywhere.v1.ModelInfo` the commons registry stores.
 *
 * The entry declares WHAT the bundle is — its files, their roles, and its
 * archive shape — and says nothing about WHERE it lands. Storage layout is
 * commons' (`rac_model_paths_get_model_folder`, i.e.
 * `{baseDir}/RunAnywhere/Models/{framework}/{id}/`), and the download
 * orchestrator, the artifact resolver, and the cold-launch reconcile all read
 * that one authority. A staged `localPath` here would be a second, competing
 * answer: commons' own downloads would land in its folder while every load
 * looked somewhere else, and — because `local_path` presence is what
 * `overwrite_download_state_from_local_path` reads — a never-fetched row would
 * register itself as already DOWNLOADED.
 *
 * So `local_path` is left unset. Commons fills it in from exactly three places,
 * all of which agree: download completion (`self_heal_registry`), the
 * cold-launch relink (`try_reconcile_model_local_path_locked`, which requires
 * the declared descriptors to actually be complete on disk), and the load-time
 * self-heal in `rac_model_lifecycle_load_proto`.
 *
 * The role assignments are what the resolver matches on when it scans a folder,
 * which is how a VLM's mmproj and the inner directory of an extracted sherpa
 * archive are recovered.
 */
export function catalogModelInfo(id: string, entry: CatalogEntry): ModelInfo {
  const files = entry.files.map((f) => ({
    url: f.url,
    filename: f.as,
    isOptional: false,
    relativePath: f.as,
    role:
      f.as === entry.primary
        ? ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL
        : f.as === entry.mmproj
          ? ModelFileRole.MODEL_FILE_ROLE_VISION_PROJECTOR
          : ModelFileRole.MODEL_FILE_ROLE_COMPANION,
  }));
  return {
    id,
    name: entry.label ?? id,
    category: CATEGORY_OF_TYPE[entry.type],
    format: formatOf(entry),
    framework: frameworkOf(entry),
    downloadUrl: entry.files[0]?.url ?? '',
    localPath: '',
    downloadSizeBytes: entry.sizeMB ? entry.sizeMB * 1_000_000 : 0,
    contextLength: 0,
    supportsThinking: false,
    supportsLora: entry.type === 'llm',
    source: ModelSource.MODEL_SOURCE_REMOTE,
    createdAtUnixMs: 0,
    updatedAtUnixMs: 0,
    registryStatus: ModelRegistryStatus.MODEL_REGISTRY_STATUS_REGISTERED,
    ...(entry.archive
      ? {
          // An archive's `expected_files` would describe the EXTRACTED tree, and
          // a catalog row only knows the tarball's name plus the directory it
          // unpacks to (`primary`) — not the files inside it. Declaring the
          // tarball there would make the completeness check look for an archive
          // that extraction deletes, so the shape is declared and the file list
          // is left to commons' post-extraction folder scan.
          archive: {
            type: ArchiveType.ARCHIVE_TYPE_TAR_BZ2,
            structure: 0,
          },
        }
      : files.length > 1
        ? { multiFile: { files } }
        : {
            // One file, named rather than left implicit. Without a manifest the
            // cold-launch reconcile falls back to "any recognizable model file
            // in the folder will do", which relinks a row against whatever
            // happens to be lying there. `required_patterns` is what commons
            // carries into its own artifact struct for a single-file entry (the
            // descriptor list is only read off `multi_file`), so the filename is
            // declared there to be enforced.
            singleFile: {
              expectedFiles: {
                files,
                rootDirectory: '',
                requiredPatterns: [entry.primary],
                optionalPatterns: [],
              },
            },
          }),
    ...(entry.license ? { metadata: { description: '', author: '', license: entry.license, tags: [], version: '' } } : {}),
  };
}
