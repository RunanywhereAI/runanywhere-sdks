/**
 * RunAnywhere Web SDK - Model and environment types.
 *
 * Proto-aligned types live in `@runanywhere/proto-ts/*` and are
 * re-exported from `types/index.ts`. Generated model/storage shapes are
 * aliases here; browser-only environment and storage summary types remain
 * Web-local.
 */

import type {
  ModelInfo as ProtoModelInfo,
  ModelInfoMetadata as ProtoModelInfoMetadata,
  SDKEnvironment,
} from '@runanywhere/proto-ts/model_types';
import type { AccelerationPreference } from '@runanywhere/proto-ts/hardware_profile';
import type {
  StorageInfo as ProtoStorageInfo,
  StoredModel as ProtoStoredModel,
} from '@runanywhere/proto-ts/storage_types';
import type { ThinkingTagPattern as ProtoThinkingTagPattern } from '@runanywhere/proto-ts/thinking_tag_pattern';

export type ThinkingTagPattern = ProtoThinkingTagPattern;
export type ModelInfoMetadata = ProtoModelInfoMetadata;

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
