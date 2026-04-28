/**
 * RunAnywhere Web SDK - Web-only Data Models.
 *
 * Wave 2: Proto-aligned types live in `@runanywhere/proto-ts/*` and are
 * re-exported from `types/index.ts`. This file holds Web-only browser-shape
 * models (storage info, device info, etc.) that proto doesn't cover.
 */

import type {
  AccelerationPreference,
  ConfigurationSource,
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


export interface SDKInitOptions {
  apiKey?: string;
  baseURL?: string;
  environment?: SDKEnvironment;
  debug?: boolean;
  /** Hardware acceleration preference for LLM/VLM inference. */
  acceleration?: AccelerationPreference;
  /**
   * Custom URL to the WebGPU-enabled racommons-webgpu.js glue file.
   * Only used when acceleration is 'auto' or 'webgpu'.
   */
  webgpuWasmUrl?: string;
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
