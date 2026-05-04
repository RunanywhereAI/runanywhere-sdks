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
import type { CompactModelDef, ManagedModel } from './Infrastructure/ModelManager';
import type {
  STTTranscribeOptions,
  STTTranscriptionResult,
  TTSSynthesizeOptions,
} from './types/index';

/** Convenience alias for {@link SDKInitOptions}. */
export type InitializeOptions = SDKInitOptions;

/** Convenience alias for {@link STTTranscribeOptions}. */
export type TranscribeOptions = STTTranscribeOptions;

/** Convenience alias for {@link STTTranscriptionResult}. */
export type TranscribeResult = STTTranscriptionResult;

/** Convenience alias for {@link TTSSynthesizeOptions}. */
export type SynthesisOptions = TTSSynthesizeOptions;


export type { ChatMessage } from '@runanywhere/proto-ts/chat';
export { MessageRole } from '@runanywhere/proto-ts/chat';
export { ModelArtifactType } from '@runanywhere/proto-ts/model_types';


/**
 * Interface describing the public RunAnywhere API surface.
 * Implemented by the RunAnywhere object exported from this package.
 */
export interface IRunAnywhere {
  initialize(options: SDKInitOptions): Promise<void>;
  readonly isInitialized: boolean;
  registerModel(model: CompactModelDef): void;
  unregisterModel(modelId: string): void;
  availableModels(): ManagedModel[];
  getModel(modelId: string): ManagedModel | undefined;
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
