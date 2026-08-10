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
// exists — `preload.js` and `host.js` in `examples/electron/RunAnywhereAI/` both
// register at module load.
//
// Callers can also pass a HuggingFace repo id, a direct URL, or a local path, so
// an app that registers nothing still resolves those.

import * as path from 'path';

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

function formatOf(entry: CatalogEntry): ModelFormat {
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
 * `localPath` is the primary FILE for a plain single-file entry and the model's
 * DIRECTORY for anything else. That is not cosmetic: commons' artifact resolver
 * trusts a declared single-file path verbatim and only scans (applying
 * `infer_file_role`) when the entry is an archive, multi-file, or a
 * directory-based framework — the scan is what recovers a VLM's mmproj and the
 * inner directory of an extracted sherpa archive.
 */
export function catalogModelInfo(id: string, entry: CatalogEntry, root: string): ModelInfo {
  const dir = path.join(root, id);
  const files = entry.files.map((f) => ({
    url: f.url,
    filename: f.as,
    isOptional: false,
    relativePath: f.as,
    localPath: path.join(dir, f.as),
    role:
      f.as === entry.primary
        ? ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL
        : f.as === entry.mmproj
          ? ModelFileRole.MODEL_FILE_ROLE_VISION_PROJECTOR
          : ModelFileRole.MODEL_FILE_ROLE_COMPANION,
  }));
  const scanned = Boolean(entry.archive) || files.length > 1 || Boolean(entry.mmproj);
  return {
    id,
    name: entry.label ?? id,
    category: CATEGORY_OF_TYPE[entry.type],
    format: formatOf(entry),
    framework: FRAMEWORK_OF_TYPE[entry.type],
    downloadUrl: entry.files[0]?.url ?? '',
    localPath: scanned ? dir : path.join(dir, entry.primary),
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
          archive: {
            type: ArchiveType.ARCHIVE_TYPE_TAR_BZ2,
            structure: 0,
          },
        }
      : {}),
    ...(files.length > 1 ? { multiFile: { files } } : {}),
    ...(entry.license ? { metadata: { description: '', author: '', license: entry.license, tags: [], version: '' } } : {}),
  };
}
