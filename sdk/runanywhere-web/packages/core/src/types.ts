/**
 * RunAnywhere Web SDK - Public API Type Definitions
 *
 * Wave 2: this barrel re-exports proto-ts canonical types directly. The
 * legacy hand-rolled type files have been deleted; the single source of
 * truth for cross-SDK shapes is `@runanywhere/proto-ts/*`.
 */

import type { DownloadProgress } from './Infrastructure/ModelRegistry';

export type { DownloadProgress };

// All public types live under types/index.ts (proto-ts re-exports + Web-only
// ergonomic shapes for browser I/O).
export * from './types/index';

import type { SDKInitOptions } from './types/models';
import type {
  STTTranscribeOptions,
  STTTranscriptionResult,
  TTSSynthesizeOptions,
} from './types/index';
import type { ModelCategory } from './types/enums';

/** Convenience alias for {@link SDKInitOptions}. */
export type InitializeOptions = SDKInitOptions;

/** Convenience alias for {@link STTTranscribeOptions}. */
export type TranscribeOptions = STTTranscribeOptions;

/** Convenience alias for {@link STTTranscriptionResult}. */
export type TranscribeResult = STTTranscriptionResult;

/** Convenience alias for {@link TTSSynthesizeOptions}. */
export type SynthesisOptions = TTSSynthesizeOptions;


// Phase C5: re-export proto-ts ChatMessage from the canonical proto-ts module.
export type { ChatMessage as ProtoChatMessage } from '@runanywhere/proto-ts/chat';
export { MessageRole as ProtoMessageRole } from '@runanywhere/proto-ts/chat';

/** Web-side simplified chat message (string roles, no proto envelope). */
export interface ChatMessage {
  role: 'user' | 'assistant' | 'system';
  content: string;
}

/** How the model artifact is packaged (public API). */
export enum ModelArtifactType {
  SingleFile = 'single_file',
  TarGzArchive = 'tar_gz_archive',
  Directory = 'directory',
}

/** Descriptor for a model (id, url, memory, modality). Used in catalog/API. */
export interface ModelDescriptor {
  /** Unique model identifier used to reference this model in SDK calls. */
  id: string;
  /** Human-readable display name. */
  name: string;
  /** Direct download URL for the model artifact. */
  url: string;
  /** Approximate memory requirement in bytes. */
  memoryRequirement: number;
  /** Model category / modality. */
  modality?: ModelCategory;
  /** How the model artifact is packaged. Defaults to SingleFile. */
  artifactType?: ModelArtifactType;
}


/**
 * Interface describing the public RunAnywhere API surface.
 * Implemented by the RunAnywhere object exported from this package.
 */
export interface IRunAnywhere {
  initialize(options: SDKInitOptions): Promise<void>;
  readonly isInitialized: boolean;
  downloadModel(modelId: string, onProgress?: (p: DownloadProgress) => void): Promise<void>;
  cancelDownload(modelId: string): boolean;
  deleteModel(modelId: string): Promise<void>;
  deleteAllModels(): Promise<void>;
  refreshModelRegistry(options?: {
    includeRemoteCatalog?: boolean;
    rescanLocal?: boolean;
    pruneOrphans?: boolean;
  }): boolean;
  loadModel(modelId: string): Promise<boolean>;
  unloadAll(): Promise<void>;
  shutdown(): void;
}
