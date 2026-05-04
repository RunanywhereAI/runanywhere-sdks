/**
 * RunAnywhere Web SDK - Model and environment types.
 *
 * Wave 2: Proto-aligned types live in `@runanywhere/proto-ts/*` and are
 * re-exported from `types/index.ts`. Generated model/storage shapes are
 * aliases here; browser-only environment and storage summary types remain
 * Web-local.
 */

import type {
  AccelerationPreference,
  SDKEnvironment,
} from './enums';
import type {
  ModelInfo as ProtoModelInfo,
} from '@runanywhere/proto-ts/model_types';
import type {
  StorageInfo as ProtoStorageInfo,
  StoredModel as ProtoStoredModel,
} from '@runanywhere/proto-ts/storage_types';

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

export type ModelInfo = ProtoModelInfo;


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

export type StorageInfo = ProtoStorageInfo;
export type StoredModel = ProtoStoredModel;

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
