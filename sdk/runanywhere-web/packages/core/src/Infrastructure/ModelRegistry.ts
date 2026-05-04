/**
 * Model Registry - Model catalog management
 *
 * Manages the list of registered models, their statuses, and notifies
 * listeners when the catalog changes. Extracted from ModelManager to keep
 * catalog concerns separate from download/load orchestration.
 */

import { EventBus } from '../Foundation/EventBus';
import { ModelCategory, LLMFramework, ModelStatus, SDKEventType } from '../types/enums';
import { DownloadProgress as ProtoDownloadProgress } from '@runanywhere/proto-ts/download_service';
import { ModelRegistryAdapter } from '../Adapters/ModelRegistryAdapter';
import {
  AccelerationPreference as ProtoAccelerationPreference,
  ArchiveStructure as ProtoArchiveStructure,
  ArchiveType as ProtoArchiveType,
  ModelArtifactType as ProtoModelArtifactType,
  ModelFormat as ProtoModelFormat,
  ModelSource as ProtoModelSource,
  type ModelInfo as ProtoModelInfo,
} from '@runanywhere/proto-ts/model_types';

// Re-export SDK enums for convenience (consumers can import from either location)
export { ModelCategory, LLMFramework, ModelStatus };

/**
 * Canonical `DownloadProgress` is now the proto-generated message
 * (`runanywhere.v1.DownloadProgress` from `idl/download_service.proto`).
 * Re-exported under the historical name for consumer ergonomics.
 */
export type DownloadProgress = ProtoDownloadProgress;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/**
 * For multi-file models (VLM, STT, TTS), describes additional files
 * that need to be downloaded alongside the main URL.
 */
export interface ModelFileDescriptor {
  /** Download URL */
  url: string;
  /** Filename to store as (used for OPFS key and FS path) */
  filename: string;
  /** Optional: size in bytes (for progress estimation) */
  sizeBytes?: number;
  /**
   * Optional lowercase hex SHA-256 checksum of the downloaded bytes.
   * When populated, the downloader verifies the hash after download
   * and deletes the stored bytes on mismatch.
   */
  checksumSha256?: string;
}

/**
 * A model being managed by the ModelManager.
 * Tracks download state, load state, and file locations.
 *
 * Named `ManagedModel` to avoid collision with the SDK's existing
 * `ModelInfo` type in types/models.ts (which describes C++ bridge models).
 */
export interface ManagedModel {
  id: string;
  name: string;
  /** Primary download URL (single file models) or archive URL */
  url: string;
  framework: LLMFramework;
  modality?: ModelCategory;
  memoryRequirement?: number;
  status: ModelStatus;
  downloadProgress?: number;
  error?: string;
  sizeBytes?: number;

  /**
   * Optional lowercase hex SHA-256 checksum of the primary downloaded file.
   * When populated, the downloader recomputes the hash after download via
   * `crypto.subtle.digest` and deletes the stored bytes + throws if the
   * hash does not match. This gives Web the same integrity guarantee
   * that the native SDKs get via `rac_http_download_execute`'s inline
   * `expected_sha256_hex` check.
   */
  checksumSha256?: string;

  /**
   * For multi-file models: additional files to download.
   * The main 'url' is still the primary file; these are extras.
   * For VLM: includes the mmproj file.
   * For STT/TTS: encoder/decoder/tokens files.
   */
  additionalFiles?: ModelFileDescriptor[];

  /**
   * Whether the main URL is an archive (tar.gz) that needs extraction.
   * STT and TTS models from sherpa-onnx are typically tar.gz archives.
   */
  isArchive?: boolean;

  /**
   * Paths of extracted files after download (populated after extraction).
   * Maps logical name -> filesystem path.
   */
  extractedPaths?: Record<string, string>;

  /**
   * If true, this model must run on the CPU WASM build even when WebGPU is
   * available. Set this for models that hit the llama.cpp Flash-Attention
   * cross-backend issue (B-WEB-4-001) — e.g. Qwen / LFM2 derivatives.
   * Mirrors the inline `FA_AFFECTED_MODEL_PATTERN` heuristic; populating
   * this on a per-model basis is preferred so the runtime can stop relying
   * on regex-on-id pattern matching.
   */
  requiresCPU?: boolean;
}

export type ModelChangeCallback = (models: ManagedModel[]) => void;

// ---------------------------------------------------------------------------
// Compact Model Definition & Resolver
// ---------------------------------------------------------------------------

const HF_BASE = 'https://huggingface.co';

/**
 * Artifact types for model archives.
 * Matches Swift's `ArtifactType` — archives are downloaded as a single file
 * and extracted, while individual files are downloaded separately.
 */
export type ArtifactType = 'archive';

/** Compact model definition for the registry. */
export interface CompactModelDef {
  id: string;
  name: string;
  /** HuggingFace repo path (e.g., 'LiquidAI/LFM2-VL-450M-GGUF'). */
  repo?: string;
  /** Direct URL override for non-HuggingFace sources (e.g., GitHub). */
  url?: string;
  /**
   * Filenames in the repo. First = primary model file, rest = companions.
   * Unused when `artifactType` is 'archive' (the archive contains all files).
   */
  files?: string[];
  framework: LLMFramework;
  modality?: ModelCategory;
  memoryRequirement?: number;
  /**
   * When set to 'archive', the URL points to a .tar.gz archive that
   * bundles all model files (including espeak-ng-data for TTS).
   * Matches Swift SDK's `.archive(.tarGz, structure: .nestedDirectory)`.
   */
  artifactType?: ArtifactType;

  /**
   * Per-model "must run on CPU" flag. Use for models that hit the WebGPU FA
   * cross-backend issue (B-WEB-4-001). Backends consult `ManagedModel.requiresCPU`
   * during load-time and switch the bridge to CPU automatically. Preferred over
   * inline regex/id-pattern heuristics so the registry stays the source of truth.
   */
  requiresCPU?: boolean;
}

/** Expand a compact definition into the full ManagedModel shape (minus status). */
function resolveModelDef(def: CompactModelDef): Omit<ManagedModel, 'status'> {
  const files = def.files ?? [];
  const baseUrl = def.repo ? `${HF_BASE}/${def.repo}/resolve/main` : undefined;

  // Archive models: URL is the archive itself, no individual files
  if (def.artifactType === 'archive') {
    const archiveUrl = def.url;
    if (!archiveUrl) {
      throw new Error(`Archive model '${def.id}' must specify a 'url' for the archive.`);
    }
    return {
      id: def.id,
      name: def.name,
      url: archiveUrl,
      framework: def.framework,
      modality: def.modality,
      memoryRequirement: def.memoryRequirement,
      isArchive: true,
      ...(def.requiresCPU ? { requiresCPU: true } : {}),
    };
  }

  // Individual-file models: first file = primary, rest = additional
  const primaryUrl = def.url ?? `${baseUrl}/${files[0]}`;

  const additionalFiles: ModelFileDescriptor[] = files.slice(1).map((filename) => ({
    url: baseUrl ? `${baseUrl}/${filename}` : filename,
    filename,
  }));

  return {
    id: def.id,
    name: def.name,
    url: primaryUrl,
    framework: def.framework,
    modality: def.modality,
    memoryRequirement: def.memoryRequirement,
    ...(additionalFiles.length > 0 ? { additionalFiles } : {}),
    ...(def.requiresCPU ? { requiresCPU: true } : {}),
  };
}

function managedModelToProto(model: ManagedModel): ProtoModelInfo {
  const now = Date.now();
  const archiveType = inferArchiveType(model.url);
  const base: ProtoModelInfo = {
    id: model.id,
    name: model.name,
    category: model.modality ?? ModelCategory.Language,
    format: inferModelFormat(model),
    framework: model.framework,
    downloadUrl: model.url,
    localPath: '',
    downloadSizeBytes: model.sizeBytes ?? 0,
    contextLength: 0,
    supportsThinking: false,
    supportsLora: false,
    description: '',
    source: model.url ? ProtoModelSource.MODEL_SOURCE_REMOTE : ProtoModelSource.MODEL_SOURCE_LOCAL,
    createdAtUnixMs: now,
    updatedAtUnixMs: now,
    singleFile: undefined,
    archive: undefined,
    multiFile: undefined,
    customStrategyId: undefined,
    builtIn: undefined,
    artifactType: ProtoModelArtifactType.MODEL_ARTIFACT_TYPE_SINGLE_FILE,
    expectedFiles: undefined,
    accelerationPreference: model.requiresCPU
      ? ProtoAccelerationPreference.ACCELERATION_PREFERENCE_CPU
      : undefined,
    routingPolicy: undefined,
  };

  if (model.isArchive) {
    return {
      ...base,
      archive: {
        type: archiveType,
        structure: ProtoArchiveStructure.ARCHIVE_STRUCTURE_NESTED_DIRECTORY,
        requiredPatterns: [],
        optionalPatterns: [],
      },
      artifactType: archiveType === ProtoArchiveType.ARCHIVE_TYPE_ZIP
        ? ProtoModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE
        : ProtoModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE,
    };
  }

  if (model.additionalFiles && model.additionalFiles.length > 0) {
    return {
      ...base,
      multiFile: {
        files: model.additionalFiles.map((file) => ({
          url: file.url,
          filename: file.filename,
          isRequired: true,
          sizeBytes: file.sizeBytes,
          checksum: file.checksumSha256,
        })),
      },
      artifactType: ProtoModelArtifactType.MODEL_ARTIFACT_TYPE_DIRECTORY,
    };
  }

  return {
    ...base,
    singleFile: { requiredPatterns: [], optionalPatterns: [] },
  };
}

function protoToManagedModel(proto: ProtoModelInfo, previous?: ManagedModel): ManagedModel {
  const additionalFiles = proto.multiFile?.files.map((file) => ({
    url: file.url,
    filename: file.filename,
    sizeBytes: file.sizeBytes,
    checksumSha256: file.checksum,
  })) ?? previous?.additionalFiles;
  const isArchive = proto.archive !== undefined ||
    proto.artifactType === ProtoModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE ||
    proto.artifactType === ProtoModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE ||
    previous?.isArchive === true;

  return {
    id: proto.id,
    name: proto.name || previous?.name || proto.id,
    url: proto.downloadUrl || previous?.url || '',
    framework: proto.framework,
    modality: proto.category || previous?.modality,
    memoryRequirement: previous?.memoryRequirement,
    status: previous?.status ?? ModelStatus.Registered,
    downloadProgress: previous?.downloadProgress,
    error: previous?.error,
    sizeBytes: proto.downloadSizeBytes || previous?.sizeBytes,
    checksumSha256: previous?.checksumSha256,
    ...(additionalFiles && additionalFiles.length > 0 ? { additionalFiles } : {}),
    ...(isArchive ? { isArchive: true } : {}),
    ...(previous?.extractedPaths ? { extractedPaths: previous.extractedPaths } : {}),
    ...(proto.accelerationPreference === ProtoAccelerationPreference.ACCELERATION_PREFERENCE_CPU ||
      previous?.requiresCPU ? { requiresCPU: true } : {}),
  };
}

function inferModelFormat(model: ManagedModel): ProtoModelFormat {
  const candidate = `${model.url} ${model.additionalFiles?.map((f) => f.filename).join(' ') ?? ''}`.toLowerCase();
  if (candidate.includes('.gguf')) return ProtoModelFormat.MODEL_FORMAT_GGUF;
  if (candidate.includes('.ggml')) return ProtoModelFormat.MODEL_FORMAT_GGML;
  if (candidate.includes('.onnx')) return ProtoModelFormat.MODEL_FORMAT_ONNX;
  if (candidate.includes('.ort')) return ProtoModelFormat.MODEL_FORMAT_ORT;
  if (candidate.includes('.bin')) return ProtoModelFormat.MODEL_FORMAT_BIN;
  if (candidate.includes('.zip')) return ProtoModelFormat.MODEL_FORMAT_ZIP;
  if (
    model.framework === LLMFramework.ONNX ||
    model.framework === LLMFramework.Sherpa ||
    model.modality === ModelCategory.SpeechRecognition ||
    model.modality === ModelCategory.SpeechSynthesis ||
    model.modality === ModelCategory.VoiceActivityDetection
  ) {
    return ProtoModelFormat.MODEL_FORMAT_ONNX;
  }
  if (model.framework === LLMFramework.LlamaCpp) return ProtoModelFormat.MODEL_FORMAT_GGUF;
  return ProtoModelFormat.MODEL_FORMAT_UNKNOWN;
}

function inferArchiveType(url: string): ProtoArchiveType {
  const lower = url.toLowerCase();
  if (lower.endsWith('.zip')) return ProtoArchiveType.ARCHIVE_TYPE_ZIP;
  if (lower.endsWith('.tar.bz2')) return ProtoArchiveType.ARCHIVE_TYPE_TAR_BZ2;
  if (lower.endsWith('.tar.xz')) return ProtoArchiveType.ARCHIVE_TYPE_TAR_XZ;
  return ProtoArchiveType.ARCHIVE_TYPE_TAR_GZ;
}

function patchTouchesProtoMetadata(patch: Partial<ManagedModel>): boolean {
  return 'name' in patch ||
    'url' in patch ||
    'framework' in patch ||
    'modality' in patch ||
    'sizeBytes' in patch ||
    'checksumSha256' in patch ||
    'additionalFiles' in patch ||
    'isArchive' in patch ||
    'requiresCPU' in patch;
}

// ---------------------------------------------------------------------------
// Model Registry
// ---------------------------------------------------------------------------

/**
 * ModelRegistry — manages the model catalog, status tracking, and listener
 * notifications. Does NOT handle downloads or loading.
 */
export class ModelRegistry {
  private models: ManagedModel[] = [];
  private listeners: ModelChangeCallback[] = [];
  private refreshingFromProtoRegistry = false;

  constructor() {
    ModelRegistryAdapter.onDefaultModuleReady((adapter) => {
      this.syncToProtoRegistry(adapter);
    });
  }

  // --- Registration ---

  /**
   * Register a catalog of models. Resolves compact definitions into full
   * ManagedModel entries and upserts them into the catalog.
   *
   * Semantics: entries are appended; if an entry with the same `id` is
   * already registered, its definition is replaced in place (status and
   * any runtime state are reset to `Registered` because a re-register
   * signals the caller wants the fresh definition to take effect).
   *
   * This is an upsert (not a wipe-and-replace) so the canonical per-entry
   * loop pattern — `for (m of catalog) registerModel(m)` — used by all 5
   * example apps accumulates the full catalog rather than leaving only
   * the last entry (G-DV28).
   *
   * @returns The resolved models array (callers can use this for further checks).
   */
  registerModels(defs: CompactModelDef[]): ManagedModel[] {
    const resolved = defs.map(resolveModelDef);
    const byId = new Map(this.models.map((m) => [m.id, m]));
    for (const r of resolved) {
      byId.set(r.id, { ...r, status: ModelStatus.Registered });
    }
    this.models = Array.from(byId.values());
    this.registerModelsWithProtoRegistry(this.models.filter((m) => defs.some((def) => def.id === m.id)));
    this.notifyListeners();
    EventBus.shared.emit('model.registered', SDKEventType.Model, { count: defs.length });
    return this.getModels();
  }

  /**
   * Add a single model to the registry without replacing existing ones.
   * Used for importing models via file picker or drag-and-drop.
   * If a model with the same ID already exists, this is a no-op.
   */
  addModel(model: ManagedModel): void {
    if (this.models.some((m) => m.id === model.id)) return;
    this.models.push(model);
    this.registerModelsWithProtoRegistry([model]);
    this.notifyListeners();
  }

  // --- Queries ---

  getModels(): ManagedModel[] {
    this.refreshFromProtoRegistry(false);
    return [...this.models];
  }

  getModel(id: string): ManagedModel | undefined {
    this.refreshModelFromProtoRegistry(id);
    return this.models.find((m) => m.id === id);
  }

  getModelsByCategory(category: ModelCategory): ManagedModel[] {
    return this.getModels().filter((m) => m.modality === category);
  }

  getModelsByFramework(framework: LLMFramework): ManagedModel[] {
    return this.getModels().filter((m) => m.framework === framework);
  }

  getLLMModels(): ManagedModel[] {
    return this.getModels().filter((m) => m.modality === ModelCategory.Language);
  }

  getVLMModels(): ManagedModel[] {
    return this.getModels().filter((m) => m.modality === ModelCategory.Multimodal);
  }

  getSTTModels(): ManagedModel[] {
    return this.getModels().filter((m) => m.modality === ModelCategory.SpeechRecognition);
  }

  getTTSModels(): ManagedModel[] {
    return this.getModels().filter((m) => m.modality === ModelCategory.SpeechSynthesis);
  }

  getVADModels(): ManagedModel[] {
    return this.getModels().filter((m) => m.modality === ModelCategory.VoiceActivityDetection);
  }

  // --- Status tracking ---

  updateModel(id: string, patch: Partial<ManagedModel>): void {
    this.models = this.models.map((m) => (m.id === id ? { ...m, ...patch } : m));
    const updated = this.models.find((m) => m.id === id);
    if (updated && patchTouchesProtoMetadata(patch)) this.updateModelWithProtoRegistry(updated);
    this.notifyListeners();
  }

  removeModel(id: string): void {
    const before = this.models.length;
    this.models = this.models.filter((m) => m.id !== id);
    if (this.models.length === before) return;
    this.protoAdapter()?.remove(id);
    this.notifyListeners();
  }

  // --- Listener / onChange pattern ---

  onChange(callback: ModelChangeCallback): () => void {
    this.listeners.push(callback);
    return () => {
      this.listeners = this.listeners.filter((l) => l !== callback);
    };
  }

  private notifyListeners(): void {
    const snapshot = [...this.models];
    for (const listener of this.listeners) {
      listener(snapshot);
    }
  }

  private protoAdapter(): ModelRegistryAdapter | null {
    const adapter = ModelRegistryAdapter.tryDefault();
    if (!adapter?.supportsProtoRegistry()) return null;
    return adapter;
  }

  private registerModelsWithProtoRegistry(models: ManagedModel[]): void {
    const adapter = this.protoAdapter();
    if (!adapter) return;
    for (const model of models) {
      adapter.register(managedModelToProto(model));
    }
    this.refreshFromProtoRegistry(false, adapter);
  }

  private updateModelWithProtoRegistry(model: ManagedModel): void {
    const adapter = this.protoAdapter();
    if (!adapter) return;
    if (!adapter.update(managedModelToProto(model))) {
      adapter.register(managedModelToProto(model));
    }
  }

  private syncToProtoRegistry(adapter: ModelRegistryAdapter): void {
    if (!adapter.supportsProtoRegistry()) return;
    for (const model of this.models) {
      adapter.register(managedModelToProto(model));
    }
    this.refreshFromProtoRegistry(true, adapter);
  }

  private refreshModelFromProtoRegistry(id: string): void {
    const adapter = this.protoAdapter();
    if (!adapter) return;
    const proto = adapter.get(id);
    if (!proto) return;

    const index = this.models.findIndex((m) => m.id === id);
    const previous = index >= 0 ? this.models[index] : undefined;
    const managed = protoToManagedModel(proto, previous);
    if (index >= 0) {
      this.models[index] = managed;
    } else {
      this.models.push(managed);
    }
  }

  private refreshFromProtoRegistry(notify: boolean, adapter = this.protoAdapter()): boolean {
    if (!adapter) return false;
    if (this.refreshingFromProtoRegistry) return false;

    this.refreshingFromProtoRegistry = true;
    try {
      const list = adapter.list();
      if (!list) return false;

      const previousById = new Map(this.models.map((m) => [m.id, m]));
      const protoById = new Map(list.models.map((m) => [m.id, m]));
      const seen = new Set<string>();
      const next: ManagedModel[] = [];

      for (const existing of this.models) {
        const proto = protoById.get(existing.id);
        if (!proto) {
          next.push(existing);
          continue;
        }
        next.push(protoToManagedModel(proto, existing));
        seen.add(existing.id);
      }

      for (const proto of list.models) {
        if (!seen.has(proto.id)) {
          next.push(protoToManagedModel(proto, previousById.get(proto.id)));
        }
      }

      this.models = next;
      if (notify) this.notifyListeners();
      return true;
    } finally {
      this.refreshingFromProtoRegistry = false;
    }
  }
}
