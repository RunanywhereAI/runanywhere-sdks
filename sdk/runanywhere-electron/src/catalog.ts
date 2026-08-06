// catalog.ts — the catalog REGISTRY, not a catalog.
//
// The SDK owns the entry SHAPE and the lookup surface; the APP owns WHICH models
// it offers. That split matches every other platform in this repo (iOS
// `ModelCatalogBootstrap.swift`, Android `ModelCatalog.kt`, web
// `model-catalog.ts` — all in `examples/`, none in an SDK), and it is what lets
// two apps ship different model lists against one SDK build.
//
// An app registers its table once per PROCESS, and there are two: the renderer
// preload (which exposes `catalog()` to the page) and the forked utility host
// (which downloads and resolves). See `examples/electron/RunAnywhereAI/`:
// `preload.js` and `host.js` each register before loading the SDK entry point.
//
// Callers can also pass a HuggingFace repo id, a direct URL, or a local path, so
// an app that registers nothing still resolves those.

export type ModelType = 'llm' | 'vlm' | 'embedder' | 'stt' | 'tts';

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
