/**
 * RunAnywhere Web SDK - VLM Types (LlamaCpp Backend).
 *
 * Wave 2: The proto VLM result is intentionally minimal (text + 5 token
 * counters). The llama.cpp WASM backend additionally surfaces image-encoding
 * telemetry and hardware acceleration mode that don't fit in the proto wire
 * shape. This module defines those Web-only ergonomic types and re-exports
 * proto canonical types where they suffice.
 */

import type {
  VLMImage as ProtoVLMImage,
  VLMGenerationOptions as ProtoVLMGenerationOptions,
  VLMResult,
} from '@runanywhere/proto-ts/vlm_options';
export { VLMImageFormat } from '@runanywhere/proto-ts/vlm_options';

export type VLMImage = ProtoVLMImage;

/** Backend-only knobs that are not part of the cross-SDK VLM proto surface. */
export type VLMGenerationOptions = Partial<Omit<ProtoVLMGenerationOptions, 'prompt'>> & {
  systemPrompt?: string;
  modelFamily?: number;
  streaming?: boolean;
};

export type VLMGenerationResult = VLMResult;

export interface VLMStreamingResult {
  result: Promise<VLMGenerationResult>;
  tokens: AsyncIterable<string>;
  cancel: () => void;
}

/** llama.cpp-specific VLM model architecture families. */
export enum VLMModelFamily {
  Auto = 0,
  Qwen2VL = 1,
  SmolVLM = 2,
  LLaVA = 3,
  Custom = 99,
}
