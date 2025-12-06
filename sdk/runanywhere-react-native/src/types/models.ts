/**
 * RunAnywhere React Native SDK - Data Models
 *
 * These interfaces match the iOS Swift SDK data structures.
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/
 */

import {
  ConfigurationSource,
  ExecutionTarget,
  HardwareAcceleration,
  LLMFramework,
  ModelCategory,
  ModelFormat,
  SDKEnvironment,
} from './enums';

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
}

// ============================================================================
// Generation Types
// ============================================================================

/**
 * Performance metrics for generation
 * Reference: GenerationResult.swift
 */
export interface PerformanceMetrics {
  /** Time to first token in milliseconds */
  timeToFirstTokenMs?: number;

  /** Tokens generated per second */
  tokensPerSecond?: number;

  /** Total inference time in milliseconds */
  inferenceTimeMs: number;
}

/**
 * Structured output validation result
 */
export interface StructuredOutputValidation {
  /** Whether the output is valid */
  isValid: boolean;

  /** Validation errors */
  errors: string[];

  /** Corrected output if applicable */
  corrected?: string;
}

/**
 * Structured output configuration
 */
export interface StructuredOutputConfig {
  /** JSON schema for validation */
  schema: string;

  /** Output format (json, xml, etc.) */
  format: string;

  /** Whether to enforce strict validation */
  strict: boolean;
}

/**
 * Result of a text generation request
 * Reference: GenerationResult.swift
 */
export interface GenerationResult {
  /** Generated text (with thinking content removed if extracted) */
  text: string;

  /** Thinking/reasoning content extracted from the response */
  thinkingContent?: string;

  /** Number of tokens used */
  tokensUsed: number;

  /** Model used for generation */
  modelUsed: string;

  /** Latency in milliseconds */
  latencyMs: number;

  /** Execution target (device/cloud/hybrid) */
  executionTarget: ExecutionTarget;

  /** Amount saved by using on-device execution */
  savedAmount: number;

  /** Framework used for generation (if on-device) */
  framework?: LLMFramework;

  /** Hardware acceleration used */
  hardwareUsed: HardwareAcceleration;

  /** Memory used during generation (in bytes) */
  memoryUsed: number;

  /** Detailed performance metrics */
  performanceMetrics: PerformanceMetrics;

  /** Structured output validation result */
  structuredOutputValidation?: StructuredOutputValidation;

  /** Number of tokens used for thinking/reasoning */
  thinkingTokens?: number;

  /** Number of tokens in the actual response content */
  responseTokens: number;
}

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

  /** Structured output configuration */
  structuredOutput?: StructuredOutputConfig;

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

/**
 * STT segment with timing information
 */
export interface STTSegment {
  /** Transcribed text */
  text: string;

  /** Start time in seconds */
  startTime: number;

  /** End time in seconds */
  endTime: number;

  /** Speaker ID if diarization is enabled */
  speakerId?: string;

  /** Confidence score */
  confidence: number;
}

/**
 * STT alternative transcription
 */
export interface STTAlternative {
  /** Alternative text */
  text: string;

  /** Confidence score */
  confidence: number;
}

/**
 * Speech-to-text result
 */
export interface STTResult {
  /** Main transcription text */
  text: string;

  /** Segments with timing */
  segments: STTSegment[];

  /** Detected language */
  language?: string;

  /** Overall confidence */
  confidence: number;

  /** Duration in seconds */
  duration: number;

  /** Alternative transcriptions */
  alternatives: STTAlternative[];
}

/**
 * STT options for transcription
 */
export interface STTOptions {
  /** Language code (e.g., 'en', 'es') */
  language?: string;

  /** Enable punctuation */
  punctuation?: boolean;

  /** Enable speaker diarization */
  diarization?: boolean;

  /** Enable word timestamps */
  wordTimestamps?: boolean;

  /** Sample rate */
  sampleRate?: number;
}

/**
 * TTS configuration
 */
export interface TTSConfiguration {
  /** Voice identifier */
  voice?: string;

  /** Speech rate (0.5 - 2.0) */
  rate?: number;

  /** Pitch (0.5 - 2.0) */
  pitch?: number;

  /** Volume (0.0 - 1.0) */
  volume?: number;
}

/**
 * TTS synthesis result
 */
export interface TTSResult {
  /** Base64 encoded audio data */
  audio: string;

  /** Sample rate of the audio */
  sampleRate: number;

  /** Number of samples */
  numSamples: number;

  /** Duration in seconds */
  duration: number;
}

/**
 * VAD configuration
 */
export interface VADConfiguration {
  /** Energy threshold */
  energyThreshold?: number;

  /** Sample rate */
  sampleRate?: number;

  /** Frame length in milliseconds */
  frameLength?: number;

  /** Enable auto calibration */
  autoCalibration?: boolean;
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
  /** API key for authentication */
  apiKey: string;

  /** Base URL for API requests */
  baseURL: string;

  /** SDK environment */
  environment?: SDKEnvironment;

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
