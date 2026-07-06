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
  /** Optional development-mode device registration build token (dev-mode parity with Swift). */
  buildToken?: string;
  /** Optional host app/site identifier for device registration metadata. Defaults to location.origin on Web. */
  appIdentifier?: string;
  /** Optional host app/site display name for device registration metadata. Defaults to document metadata/title on Web. */
  appName?: string;
  /** Optional host app/site version. Omit when the app does not have a real version. */
  appVersion?: string;
  /** Optional host app/site build number. Omit when the app does not have a real build number. */
  appBuild?: string;
  /** Hardware acceleration preference for LLM/VLM inference. Web-only (WebGPU platform option); no Swift counterpart. */
  acceleration?: AccelerationPreference;
  /**
   * Custom URL to the WebGPU-enabled racommons-webgpu.js glue file.
   * Only used when acceleration is 'auto' or 'webgpu'.
   * Web-only (WebGPU platform option); no Swift counterpart.
   */
  webgpuWasmUrl?: string;
}

export type StorageInfo = ProtoStorageInfo;
export type StoredModel = ProtoStoredModel;
