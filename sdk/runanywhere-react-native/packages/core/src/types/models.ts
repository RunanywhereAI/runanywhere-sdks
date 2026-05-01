/**
 * RunAnywhere React Native SDK - Data Models
 *
 * These interfaces match the iOS Swift SDK data structures and
 * describe the JS-runtime shape exchanged with the native bridge.
 * The canonical proto-encoded counterparts live in
 * `@runanywhere/proto-ts/storage_types` (storage models) and
 * `@runanywhere/proto-ts/llm_options` (perf metrics) and are
 * re-exported under `*Proto` aliases.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/
 */

import type {
  ConfigurationSource,
  ExecutionTarget,
  HardwareAcceleration,
  LLMFramework,
  ModelCategory,
  ModelFormat,
  SDKEnvironment,
} from './enums';

// Canonical proto-encoded storage / model-info messages.
export type {
  DeviceStorageInfo as DeviceStorageInfoProto,
  AppStorageInfo as AppStorageInfoProto,
  ModelStorageMetrics as ModelStorageMetricsProto,
  StorageInfo as StorageInfoProto,
  StorageAvailability as StorageAvailabilityProto,
  StoredModel as StoredModelProto,
} from '@runanywhere/proto-ts/storage_types';

// ============================================================================
// Model Information
// ============================================================================

/**
 * Thinking tag pattern for reasoning models
 */
export interface ThinkingTagPattern {
  openTag: string;
  closeTag: string;
}

/**
 * Model metadata
 */
export interface ModelInfoMetadata {
  description?: string;
  author?: string;
  license?: string;
  tags?: string[];
  version?: string;
}

/**
 * Information about a model
 * Reference: ModelInfo.swift
 */
export interface ModelInfo {
  /** Unique identifier */
  id: string;

  /** Human-readable name */
  name: string;

  /** Model category (language, speech, vision, etc.) */
  category: ModelCategory;

  /** Model file format */
  format: ModelFormat;

  /** Download URL (if remote) */
  downloadURL?: string;

  /** Local file path (if downloaded) */
  localPath?: string;

  /** Download size in bytes */
  downloadSize?: number;

  /** Memory required to run the model in bytes */
  memoryRequired?: number;

  /** Compatible frameworks */
  compatibleFrameworks: LLMFramework[];

  /** Preferred framework for this model */
  preferredFramework?: LLMFramework;

  /** Context length for language models */
  contextLength?: number;

  /** Whether the model supports thinking/reasoning */
  supportsThinking: boolean;

  /** Custom thinking pattern if supportsThinking */
  thinkingPattern?: ThinkingTagPattern;

  /** Optional metadata */
  metadata?: ModelInfoMetadata;

  /** Configuration source */
  source: ConfigurationSource;

  /** Creation timestamp */
  createdAt: string;

  /** Last update timestamp */
  updatedAt: string;

  /** Whether sync is pending */
  syncPending: boolean;

  /** Last used timestamp */
  lastUsed?: string;

  /** Usage count */
  usageCount: number;

  /** Whether the model is downloaded */
  isDownloaded: boolean;

  /** Whether the model is available for use */
  isAvailable: boolean;

  /**
   * Optional lowercase hex SHA-256 checksum of the downloaded artifact.
   * When populated, forwarded to the native `rac_http_download_execute`
   * call via `expected_sha256_hex` so the libcurl write path verifies
   * the hash inline and fails with `RAC_HTTP_DL_CHECKSUM_FAILED` on
   * mismatch. Matches the Swift/Kotlin/Flutter contract.
   */
  checksumSha256?: string;
}

// ============================================================================
// Model Compatibility
// ============================================================================

/**
 * Result of a model compatibility check
 */
export interface ModelCompatibilityResult {
  /** Overall compatibility (canRun AND canFit) */
  isCompatible: boolean;

  /** Whether the device has enough RAM to run the model */
  canRun: boolean;

  /** Whether the device has enough free storage to store the model */
  canFit: boolean;

  /** Model's required RAM in bytes */
  requiredMemory: number;

  /** Device's available RAM in bytes */
  availableMemory: number;

  /** Model's required storage in bytes */
  requiredStorage: number;

  /** Device's available storage in bytes */
  availableStorage: number;
}

// ============================================================================
// Generation Types
// ============================================================================


/**
 * Options for text generation
 * Reference: GenerationOptions.swift
 */
export interface GenerationOptions {
  /** Maximum number of tokens to generate */
  maxTokens?: number;

  /** Temperature for sampling (0.0 - 1.0) */
  temperature?: number;

  /** Top-p sampling parameter */
  topP?: number;

  /** Enable real-time tracking for cost dashboard */
  enableRealTimeTracking?: boolean;

  /** Stop sequences */
  stopSequences?: string[];

  /** Enable streaming mode */
  streamingEnabled?: boolean;

  /** Preferred execution target */
  preferredExecutionTarget?: ExecutionTarget;

  /** Preferred framework for generation */
  preferredFramework?: LLMFramework;

  /** System prompt to define AI behavior */
  systemPrompt?: string;
}


// ============================================================================
// Voice Types
// ============================================================================

/**
 * Voice audio chunk for streaming
 */
export interface VoiceAudioChunk {
  /** Float32 audio samples (base64 encoded) */
  samples: string;

  /** Timestamp */
  timestamp: number;

  /** Sample rate */
  sampleRate: number;

  /** Number of channels */
  channels: number;

  /** Sequence number */
  sequenceNumber: number;

  /** Whether this is the final chunk */
  isFinal: boolean;
}

// ============================================================================
// Configuration Types
// ============================================================================

/**
 * Configuration data returned by the native SDK
 */
export interface ConfigurationData {
  /** Current environment */
  environment: SDKEnvironment;

  /** API key (masked for security) */
  apiKey?: string;

  /** Base URL for API requests */
  baseURL?: string;

  /** Configuration source */
  source: ConfigurationSource;

  /** Default generation settings */
  defaultGenerationSettings?: DefaultGenerationSettings;

  /** Feature flags */
  featureFlags?: Record<string, boolean>;

  /** Last updated timestamp */
  lastUpdated?: string;

  /** Additional configuration values */
  [key: string]: unknown;
}

/**
 * SDK initialization options
 */
export interface SDKInitOptions {
  /** API key for authentication (production/staging) */
  apiKey?: string;

  /** Base URL for API requests (production: Railway endpoint) */
  baseURL?: string;

  /** SDK environment */
  environment?: SDKEnvironment;

  /**
   * Supabase project URL (development mode)
   * When set, SDK makes calls directly to Supabase
   */
  supabaseURL?: string;

  /**
   * Supabase anon key (development mode)
   */
  supabaseKey?: string;

  /**
   * Build token for device registration.
   *
   * Resolution order (highest precedence first):
   *   1. This option.
   *   2. `RUNANYWHERE_BUILD_TOKEN` environment variable (build-time).
   *   3. Native development-mode fallback (development environment only).
   *
   * Production/staging apps must provide this via option or env var.
   */
  buildToken?: string;

  /** Enable debug logging */
  debug?: boolean;
}

/**
 * Default generation settings
 */
export interface DefaultGenerationSettings {
  maxTokens: number;
  temperature: number;
  topP: number;
}

/**
 * Storage information
 */
export interface StorageInfo {
  /** Total storage available in bytes */
  totalSpace: number;

  /** Storage used by SDK in bytes */
  usedSpace: number;

  /** Free space available in bytes */
  freeSpace: number;

  /** Models storage path */
  modelsPath: string;
}

/**
 * Stored model information
 */
export interface StoredModel {
  /** Model ID */
  id: string;

  /** Model name */
  name: string;

  /** Size on disk in bytes */
  sizeOnDisk: number;

  /** Download date */
  downloadedAt: string;

  /** Last used date */
  lastUsed?: string;
}

// ============================================================================
// Device Types
// ============================================================================

/**
 * Device information
 */
export interface DeviceInfoData {
  /** Device model */
  model: string;

  /** Device name */
  name: string;

  /** OS version */
  osVersion: string;

  /** Chip/processor name */
  chipName: string;

  /** Total memory in bytes */
  totalMemory: number;

  /** Whether device has Neural Engine */
  hasNeuralEngine: boolean;

  /** Processor architecture */
  architecture: string;
}

/**
 * Framework availability information
 */
export interface FrameworkAvailability {
  /** Framework */
  framework: LLMFramework;

  /** Whether available */
  isAvailable: boolean;

  /** Reason if not available */
  reason?: string;
}

// ============================================================================
// Component Types
// ============================================================================

/**
 * Initialization result for components
 */
export interface InitializationResult {
  /** Whether initialization succeeded */
  success: boolean;

  /** Components that are ready */
  readyComponents: string[];

  /** Components that failed */
  failedComponents: string[];

  /** Error message if failed */
  error?: string;
}

/**
 * Component health information
 */
export interface ComponentHealth {
  /** Component identifier */
  component: string;

  /** Whether healthy */
  isHealthy: boolean;

  /** Last check timestamp */
  lastCheck: string;

  /** Memory usage in bytes */
  memoryUsage?: number;

  /** Error message if unhealthy */
  error?: string;
}
