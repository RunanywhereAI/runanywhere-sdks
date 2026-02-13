/**
 * Model Registry - Model catalog management
 *
 * Manages the list of registered models, their statuses, and notifies
 * listeners when the catalog changes. Extracted from ModelManager to keep
 * catalog concerns separate from download/load orchestration.
 */

import { EventBus } from '../Foundation/EventBus';
import { ModelCategory, LLMFramework, ModelStatus, SDKEventType } from '../types/enums';

// Re-export SDK enums for convenience (consumers can import from either location)
export { ModelCategory, LLMFramework, ModelStatus };

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
}

/** Structured download progress with stage information. */
export interface DownloadProgress {
  modelId: string;
  stage: import('../types/enums').DownloadStage;
  /** Overall progress 0-1 */
  progress: number;
  bytesDownloaded: number;
  totalBytes: number;
  /** Filename currently being downloaded (for multi-file models) */
  currentFile?: string;
  /** Number of files completed so far */
  filesCompleted?: number;
  /** Total number of files to download */
  filesTotal?: number;
}

export type ModelChangeCallback = (models: ManagedModel[]) => void;

// ---------------------------------------------------------------------------
// Compact Model Definition & Resolver
// ---------------------------------------------------------------------------

const HF_BASE = 'https://huggingface.co';

/** Compact model definition for the registry. */
export interface CompactModelDef {
  id: string;
  name: string;
  /** HuggingFace repo path (e.g., 'LiquidAI/LFM2-VL-450M-GGUF'). */
  repo?: string;
  /** Direct URL override for non-HuggingFace sources (e.g., GitHub). */
  url?: string;
  /** Filenames in the repo. First = primary model file, rest = companions. */
  files: string[];
  framework: LLMFramework;
  modality?: ModelCategory;
  memoryRequirement?: number;
}

/** Expand a compact definition into the full ManagedModel shape (minus status). */
function resolveModelDef(def: CompactModelDef): Omit<ManagedModel, 'status'> {
  const baseUrl = def.repo ? `${HF_BASE}/${def.repo}/resolve/main` : undefined;
  const primaryUrl = def.url ?? `${baseUrl}/${def.files[0]}`;

  const additionalFiles: ModelFileDescriptor[] = def.files.slice(1).map((filename) => ({
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
  };
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

  // --- Registration ---

  /**
   * Register a catalog of models. Resolves compact definitions into full
   * ManagedModel entries.
   *
   * @returns The resolved models array (callers can use this for further checks).
   */
  registerModels(defs: CompactModelDef[]): ManagedModel[] {
    const resolved = defs.map(resolveModelDef);
    this.models = resolved.map((m) => ({ ...m, status: ModelStatus.Registered }));
    this.notifyListeners();
    EventBus.shared.emit('model.registered', SDKEventType.Model, { count: defs.length });
    return this.getModels();
  }

  // --- Queries ---

  getModels(): ManagedModel[] {
    return [...this.models];
  }

  getModel(id: string): ManagedModel | undefined {
    return this.models.find((m) => m.id === id);
  }

  getModelsByCategory(category: ModelCategory): ManagedModel[] {
    return this.models.filter((m) => m.modality === category);
  }

  getModelsByFramework(framework: LLMFramework): ManagedModel[] {
    return this.models.filter((m) => m.framework === framework);
  }

  getLLMModels(): ManagedModel[] {
    return this.models.filter((m) => m.modality === ModelCategory.Language);
  }

  getVLMModels(): ManagedModel[] {
    return this.models.filter((m) => m.modality === ModelCategory.Multimodal);
  }

  getSTTModels(): ManagedModel[] {
    return this.models.filter((m) => m.modality === ModelCategory.SpeechRecognition);
  }

  getTTSModels(): ManagedModel[] {
    return this.models.filter((m) => m.modality === ModelCategory.SpeechSynthesis);
  }

  getVADModels(): ManagedModel[] {
    return this.models.filter((m) => m.modality === ModelCategory.Audio);
  }

  // --- Status tracking ---

  updateModel(id: string, patch: Partial<ManagedModel>): void {
    this.models = this.models.map((m) => (m.id === id ? { ...m, ...patch } : m));
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
    for (const listener of this.listeners) {
      listener(this.getModels());
    }
  }
}
