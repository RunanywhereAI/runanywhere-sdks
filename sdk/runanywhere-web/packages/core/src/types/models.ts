/**
 * RunAnywhere Web SDK - Data Models
 *
 * Mirrored from: sdk/runanywhere-react-native/packages/core/src/types/models.ts
 * Source of truth: sdk/runanywhere-swift/Sources/RunAnywhere/
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

export interface ThinkingTagPattern {
  openTag: string;
  closeTag: string;
}

export interface ModelInfoMetadata {
  description?: string;
  author?: string;
  license?: string;
  tags?: string[];
  version?: string;
}

export interface ModelInfo {
  id: string;
  name: string;
  category: ModelCategory;
  format: ModelFormat;
  downloadURL?: string;
  localPath?: string;
  downloadSize?: number;
  memoryRequired?: number;
  compatibleFrameworks: LLMFramework[];
  preferredFramework?: LLMFramework;
  contextLength?: number;
  supportsThinking: boolean;
  thinkingPattern?: ThinkingTagPattern;
  metadata?: ModelInfoMetadata;
  source: ConfigurationSource;
  createdAt: string;
  updatedAt: string;
  syncPending: boolean;
  lastUsed?: string;
  usageCount: number;
  isDownloaded: boolean;
  isAvailable: boolean;
}

export interface PerformanceMetrics {
  timeToFirstTokenMs?: number;
  tokensPerSecond?: number;
  inferenceTimeMs: number;
}

export interface GenerationResult {
  text: string;
  thinkingContent?: string;
  tokensUsed: number;
  modelUsed: string;
  latencyMs: number;
  executionTarget: ExecutionTarget;
  savedAmount: number;
  framework?: LLMFramework;
  hardwareUsed: HardwareAcceleration;
  memoryUsed: number;
  performanceMetrics: PerformanceMetrics;
  thinkingTokens?: number;
  responseTokens: number;
}

export interface GenerationOptions {
  maxTokens?: number;
  temperature?: number;
  topP?: number;
  stopSequences?: string[];
  streamingEnabled?: boolean;
  preferredExecutionTarget?: ExecutionTarget;
  preferredFramework?: LLMFramework;
  systemPrompt?: string;
}

export type LLMGenerationOptions = GenerationOptions;

export interface STTOptions {
  language?: string;
  punctuation?: boolean;
  diarization?: boolean;
  wordTimestamps?: boolean;
  sampleRate?: number;
}

export interface STTResult {
  text: string;
  segments: STTSegment[];
  language?: string;
  confidence: number;
  duration: number;
  alternatives: STTAlternative[];
}

export interface STTSegment {
  text: string;
  startTime: number;
  endTime: number;
  speakerId?: string;
  confidence: number;
}

export interface STTAlternative {
  text: string;
  confidence: number;
}

export interface TTSConfiguration {
  voice?: string;
  rate?: number;
  pitch?: number;
  volume?: number;
}

export interface TTSResult {
  audio: string;
  sampleRate: number;
  numSamples: number;
  duration: number;
}

export interface VADConfiguration {
  energyThreshold?: number;
  sampleRate?: number;
  frameLength?: number;
  autoCalibration?: boolean;
}

export interface SDKInitOptions {
  apiKey?: string;
  baseURL?: string;
  environment?: SDKEnvironment;
  debug?: boolean;
}

export interface StorageInfo {
  totalSpace: number;
  usedSpace: number;
  freeSpace: number;
  modelsPath: string;
}

export interface StoredModel {
  id: string;
  name: string;
  sizeOnDisk: number;
  downloadedAt: string;
  lastUsed?: string;
}

export interface DeviceInfoData {
  model: string;
  name: string;
  osVersion: string;
  totalMemory: number;
  architecture: string;
  /** Whether WebGPU is available */
  hasWebGPU: boolean;
  /** Whether SharedArrayBuffer is available (pthreads) */
  hasSharedArrayBuffer: boolean;
}
