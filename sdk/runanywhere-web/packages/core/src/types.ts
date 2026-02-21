/**
 * RunAnywhere Web SDK - Public API Type Definitions
 *
 * Single entry point for all public-facing types. Re-exports from types/enums
 * and types/models, and adds chat/generation/IRunAnywhere interfaces for
 * full TypeScript parity with the React Native SDK.
 */

// Re-export all enums and models (existing types)
export {
  AccelerationPreference,
  ComponentState,
  ConfigurationSource,
  DownloadStage,
  ExecutionTarget,
  FrameworkModality,
  HardwareAcceleration,
  LLMFramework,
  ModelFormat,
  ModelStatus,
  RoutingPolicy,
  SDKComponent,
  SDKEnvironment,
  SDKEventType,
} from './types/enums';

export type {
  DeviceInfoData,
  GenerationOptions,
  GenerationResult,
  ModelInfoMetadata,
  PerformanceMetrics,
  SDKInitOptions,
  STTAlternative,
  STTOptions,
  STTResult,
  STTSegment,
  StorageInfo,
  StoredModel,
  ThinkingTagPattern,
  TTSConfiguration,
  TTSResult,
  VADConfiguration,
} from './types/models';

// ---------------------------------------------------------------------------
// Aliases for spec/README convenience (match React Native naming where used)
// ---------------------------------------------------------------------------

import type {
  SDKInitOptions,
  GenerationOptions,
  STTOptions,
  STTResult,
  TTSConfiguration,
} from './types/models';
import type { ModelCategory } from './types/enums';

/** @deprecated Use SDKInitOptions. Kept for API compatibility. */
export type InitializeOptions = SDKInitOptions;

/** Alias for GenerationOptions (generate/chat options). */
export type GenerateOptions = GenerationOptions;

/** Alias for STTOptions (transcription options). */
export type TranscribeOptions = STTOptions;

/** Alias for STTResult (transcription result). */
export type TranscribeResult = STTResult;

/** Alias for TTSConfiguration (synthesis options). */
export type SynthesisOptions = TTSConfiguration;

// ---------------------------------------------------------------------------
// Chat & model descriptor types
// ---------------------------------------------------------------------------

/** A single message in a chat conversation. */
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

// ---------------------------------------------------------------------------
// IRunAnywhere interface (describes the RunAnywhere object shape)
// ---------------------------------------------------------------------------

import type { DownloadProgress } from './Infrastructure/ModelRegistry';

/**
 * Interface describing the public RunAnywhere API surface.
 * Implemented by the RunAnywhere object exported from this package.
 */
export interface IRunAnywhere {
  initialize(options: SDKInitOptions): Promise<void>;
  readonly isInitialized: boolean;
  downloadModel(modelId: string, onProgress?: (p: DownloadProgress) => void): Promise<void>;
  loadModel(modelId: string): Promise<boolean>;
  unloadAll(): Promise<void>;
  shutdown(): void;
}
