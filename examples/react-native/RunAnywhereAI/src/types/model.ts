/**
 * Model Types - Matching iOS and SDK model definitions
 *
 * Reference: sdk/runanywhere-react-native/src/types/models.ts
 */

/**
 * Model category — re-exported from `@runanywhere/core` (which re-exports the
 * canonical `ModelCategory` proto enum from `@runanywhere/proto-ts`). Keep
 * this re-export so existing example-app imports `from '../types/model'`
 * continue to resolve, but the values are the proto canonical
 * `MODEL_CATEGORY_*` numeric form, not the prior hand-rolled string form.
 */
import {
  LLMFramework,
  LLMFrameworkDisplayNames,
  ModelCategory,
  InferenceFramework,
  type ModelInfo,
  type ProtoModelInfo,
} from '@runanywhere/core';
export { LLMFramework, ModelCategory, InferenceFramework };
export { LLMFrameworkDisplayNames as FrameworkDisplayNames };
export type { ModelInfo, ProtoModelInfo };

/**
 * Model modality for filtering
 */
export enum ModelModality {
  LLM = 'llm',
  STT = 'stt',
  TTS = 'tts',
  VLM = 'vlm',
}

/**
 * Device info for model selection
 */
export interface DeviceInfo {
  /** Device model name */
  modelName: string;

  /** Chip name */
  chipName: string;

  /** Total memory in bytes */
  totalMemory: number;

  /** Available memory in bytes */
  availableMemory: number;

  /** Whether device has Neural Engine / NPU */
  hasNeuralEngine: boolean;

  /** OS version */
  osVersion: string;

  /** Whether device has GPU */
  hasGPU?: boolean;

  /** Number of CPU cores */
  cpuCores?: number;
}
